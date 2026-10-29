import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:music_player/data/audio_tags.dart';
import 'package:music_player/data/baidu_client.dart';
import 'package:music_player/data/song_details_repository.dart';
import 'package:music_player/models/drive_entry.dart';

import 'baidu_client_test.dart' show MemoryStore, credentials;
import 'baidu_file_actions_test.dart' show managedSong;

final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNoWJAAAAMkAYGhwrMzAAAAAElFTkSuQmCC',
);

class DetailsClient extends BaiduClient {
  DetailsClient() : super(MemoryStore(credentials()));
  List<DriveEntry> files = [];
  final listed = <String>[];
  final fetched = <String>[];
  @override
  Future<DirectoryPage> listDirectory(
    String dir, {
    int start = 0,
    int limit = 200,
  }) async {
    listed.add(dir);
    return DirectoryPage(files, null);
  }

  @override
  Future<http.StreamedResponse> openStream(
    DriveEntry entry, {
    int? start,
    int? end,
    dynamic control,
  }) async {
    fetched.add(entry.path);
    final bytes = entry.name.endsWith('.lrc')
        ? utf8.encode('[00:01]测试歌词')
        : entry.name.endsWith('.png')
        ? png
        : <int>[];
    return http.StreamedResponse(Stream.value(bytes), 200);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  void repositoryTest(String name, Future<void> Function() body) {
    testWidgets(name, (tester) async {
      await tester.runAsync(body);
    });
  }

  late Directory directory;
  late DetailsClient client;
  late SongDetailsRepository repo;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('song-details-');
    client = DetailsClient();
    await client.initialize();
    repo = SongDetailsRepository(directory, client)
      ..canRead = (p) => p.startsWith('/音乐/');
    await repo.initialize();
  });
  tearDown(() async {
    repo.dispose();
    await directory.delete(recursive: true);
  });
  repositoryTest(
    'reads only same-parent matching lyrics and cover and persists across restart',
    () async {
      client.files = [
        const DriveEntry(id: '8', name: '晴天.lrc', path: '/音乐/周杰伦/晴天.lrc'),
        const DriveEntry(id: '9', name: 'cover.png', path: '/音乐/周杰伦/cover.png'),
        const DriveEntry(id: '10', name: '其他.lrc', path: '/音乐/其他/其他.lrc'),
      ];
      final result = await repo.load(managedSong);
      expect(client.listed, ['/音乐/周杰伦']);
      expect(result.lyrics, '[00:01]测试歌词');
      expect(result.coverPath, isNotNull);
      expect(client.fetched, isNot(contains('/音乐/其他/其他.lrc')));
      final restored = SongDetailsRepository(directory, client)
        ..canRead = (_) => false;
      await restored.initialize();
      client.fetched.clear();
      final offline = await restored.load(managedSong);
      expect(offline.lyrics, result.lyrics);
      expect(offline.coverPath, result.coverPath);
      expect(client.fetched, isEmpty);
      restored.dispose();
    },
  );
  repositoryTest(
    'phone imports survive refresh and move without changing cloud files',
    () async {
      await repo.setLyrics(managedSong, '[00:02]我导入的歌词', '手机导入');
      await repo.setCover(managedSong, png, '手机导入');
      client.files = [
        const DriveEntry(id: '8', name: '晴天.lrc', path: '/音乐/周杰伦/晴天.lrc'),
      ];
      await repo.load(managedSong, refresh: true);
      expect(repo.cached(managedSong).lyrics, '[00:02]我导入的歌词');
      const moved = DriveEntry(id: '7', name: '晴天.mp3', path: '/音乐/流行/晴天.mp3');
      await repo.move(managedSong, moved);
      expect(repo.cached(moved).coverPath, repo.cached(managedSong).coverPath);
      expect(repo.cached(moved).lyricsSource, '手机导入');
    },
  );
  repositoryTest(
    'bounded stream cancels large bodies and rejects oversized sidecars',
    () async {
      var cancelled = false;
      final stream = Stream<List<int>>.multi((s) {
        s.add(List.filled(100, 1));
        s.add(List.filled(100, 2));
        s.onCancel = () {
          cancelled = true;
        };
      });
      final data = await SongDetailsRepository.readLimited(
        stream,
        120,
        truncate: true,
      );
      expect(data.length, 120);
      expect(cancelled, isTrue);
      await expectLater(
        SongDetailsRepository.readLimited(Stream.value(List.filled(12, 0)), 10),
        throwsFormatException,
      );
      client.files = [
        const DriveEntry(
          id: '8',
          name: '晴天.lrc',
          path: '/音乐/周杰伦/晴天.lrc',
          size: AudioTags.maxLyrics + 1,
        ),
      ];
      await repo.load(managedSong);
      expect(client.fetched, [managedSong.path]);
    },
  );
  repositoryTest(
    'unconfigured/outside root makes zero cloud requests',
    () async {
      repo.canRead = (_) => false;
      await repo.load(managedSong);
      expect(client.fetched, isEmpty);
      expect(client.listed, isEmpty);
    },
  );
}
