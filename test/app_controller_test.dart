import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_player/app_controller.dart';
import 'package:music_player/data/baidu_client.dart';
import 'package:music_player/data/offline_library.dart';
import 'package:music_player/data/transfer_manager.dart';
import 'package:music_player/models/music_directory.dart';

import 'baidu_client_test.dart' show MemoryStore, credentials, jsonResponse;
import 'support/fake_music_handler.dart';
import 'transfer_test.dart' show bytesInput, settled;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppController> createApp({
    Map<String, Object> stored = const {},
    required Future<http.Response> Function(http.Request) respond,
    bool withTransfers = false,
  }) async {
    SharedPreferences.setMockInitialValues(stored);
    final client = BaiduClient(
      MemoryStore(credentials()),
      client: MockClient(respond),
    );
    await client.initialize();
    final prefs = await SharedPreferences.getInstance();
    OfflineLibrary? library;
    TransferManager? transfers;
    if (withTransfers) {
      final temp = await Directory.systemTemp.createTemp('music-root-test-');
      addTearDown(() => temp.delete(recursive: true));
      library = OfflineLibrary(temp, prefs);
      await library.initialize();
      transfers = TransferManager(client, library);
      addTearDown(transfers.dispose);
    }
    final app = AppController(
      client,
      FakeMusicHandler(),
      prefs,
      library: library,
      transfers: transfers,
    );
    addTearDown(app.dispose);
    return app;
  }

  for (final legacyRoot in [null, '/', '/音乐/../私人']) {
    test(
      'startup with unset or invalid root $legacyRoot makes no file request',
      () async {
        var requests = 0;
        final app = await createApp(
          stored: {'music_root': ?legacyRoot, 'directory': '/私人'},
          respond: (_) async {
            requests++;
            return jsonResponse({'list': []});
          },
        );
        await app.initialize();
        await app.openLibrary();
        await app.browse('/');
        expect(requests, 0);
        expect(app.needsMusicRoot, isTrue);
        expect(app.entries, isEmpty);
        expect(app.prefs.getString('music_root'), isNull);
        expect(app.prefs.getString('directory'), isNull);
      },
    );
  }

  test(
    'stored music root rejects remembered directories outside its boundary',
    () async {
      final requested = <String>[];
      final app = await createApp(
        stored: {'music_root': '/音乐', 'directory': '/音乐备份'},
        respond: (r) async {
          requested.add(r.url.queryParameters['dir']!);
          return jsonResponse({'list': []});
        },
      );
      await app.initialize();
      expect(requested, ['/音乐']);
      expect(app.canGoUp, isFalse);
      expect(app.directory, '/音乐');
    },
  );

  test(
    'nested remembered directory stays within configured music root',
    () async {
      final requested = <String>[];
      final app = await createApp(
        stored: {'music_root': '/音乐', 'directory': '/音乐/周杰伦/专辑'},
        respond: (r) async {
          requested.add(r.url.queryParameters['dir']!);
          return jsonResponse({'list': []});
        },
      );
      await app.initialize();
      expect(requested, ['/音乐/周杰伦/专辑']);
      expect(app.canGoUp, isTrue);
    },
  );

  test(
    'explicit root is normalized and children are listed only when opened',
    () async {
      final requested = <String>[];
      final app = await createApp(
        respond: (r) async {
          final path = r.url.queryParameters['dir']!;
          requested.add(path);
          return jsonResponse({
            'list': [
              {
                'fs_id': 1,
                'server_filename': '五月天',
                'path': '$path/五月天',
                'isdir': 1,
              },
            ],
          });
        },
      );
      await app.configureMusicRoot(' /音乐//收藏/ ');
      expect(requested, ['/音乐/收藏']);
      expect(app.musicRoot, '/音乐/收藏');
      expect(app.visible.single.name, '五月天');
      await app.browse('/音乐/收藏/五月天');
      expect(requested, ['/音乐/收藏', '/音乐/收藏/五月天']);
    },
  );

  test(
    'invalid roots, parent paths and prefix siblings never reach Baidu',
    () async {
      final requested = <String>[];
      final app = await createApp(
        respond: (r) async {
          requested.add(r.url.queryParameters['dir']!);
          return jsonResponse({'list': []});
        },
      );
      for (final path in ['/', '', '音乐', '/音乐/../私人', '/音乐/./专辑', r'/音乐\私人']) {
        await expectLater(
          app.configureMusicRoot(path),
          throwsA(isA<DriveException>()),
        );
      }
      expect(requested, isEmpty);
      await app.configureMusicRoot('/收藏/音乐');
      for (final path in ['/', '/收藏', '/收藏/音乐备份', '/收藏/音乐/../私人']) {
        await app.browse(path);
        await expectLater(
          app.createFolder(path, '新歌手'),
          throwsA(isA<DriveException>()),
        );
      }
      expect(requested, ['/收藏/音乐']);
      expect(app.directory, '/收藏/音乐');
    },
  );

  test(
    'unexpected outside or deeper entries are never exposed as direct children',
    () async {
      final app = await createApp(
        respond: (_) async => jsonResponse({
          'list': [
            {
              'fs_id': 1,
              'server_filename': '五月天',
              'path': '/音乐/五月天',
              'isdir': 1,
            },
            {'fs_id': 2, 'server_filename': '私人', 'path': '/私人', 'isdir': 1},
            {
              'fs_id': 3,
              'server_filename': '专辑',
              'path': '/音乐/五月天/专辑',
              'isdir': 1,
            },
            {
              'fs_id': 4,
              'server_filename': '外部',
              'path': '/音乐/../外部',
              'isdir': 1,
            },
          ],
        }),
      );
      await app.configureMusicRoot('/音乐');
      expect(app.entries.map((e) => e.name), ['五月天']);
    },
  );

  test(
    'a late previous-root response cannot replace the newly selected library',
    () async {
      final pending = Completer<http.Response>();
      final requested = <String>[];
      final app = await createApp(
        respond: (r) async {
          final path = r.url.queryParameters['dir']!;
          requested.add(path);
          if (path == '/旧音乐') return pending.future;
          return jsonResponse({
            'list': [
              {
                'fs_id': 2,
                'server_filename': '许嵩',
                'path': '/新音乐/许嵩',
                'isdir': 1,
              },
            ],
          });
        },
      );
      final first = app.configureMusicRoot('/旧音乐');
      while (requested.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      await app.configureMusicRoot('/新音乐');
      pending.complete(
        jsonResponse({
          'list': [
            {
              'fs_id': 1,
              'server_filename': '旧歌手',
              'path': '/旧音乐/旧歌手',
              'isdir': 1,
            },
          ],
        }),
      );
      await first;
      expect(app.musicRoot, '/新音乐');
      expect(app.directory, '/新音乐');
      expect(app.entries.single.name, '许嵩');
      expect(app.prefs.getString('music_root'), '/新音乐');
    },
  );

  test('out-of-root saved remote queue is not restored', () async {
    final app = await createApp(
      stored: {
        'music_root': '/音乐',
        'playback': jsonEncode({
          'tracks': [
            {'fs_id': 1, 'name': '音乐.mp3', 'path': '/音乐/音乐.mp3'},
            {'fs_id': 2, 'name': '旧音乐.mp3', 'path': '/私人/旧音乐.mp3'},
          ],
        }),
      },
      respond: (_) async => jsonResponse({'list': []}),
    );
    await app.initialize();
    expect(app.audio.entries.map((e) => e.id), ['1']);
  });

  test('uploads and retries respect the newly selected root', () async {
    final methods = <String>[];
    final app = await createApp(
      withTransfers: true,
      respond: (r) async {
        final method = r.url.queryParameters['method']!;
        methods.add(method);
        if (method == 'list') return jsonResponse({'list': []});
        return jsonResponse({'errno': -6});
      },
    );
    await app.configureMusicRoot('/音乐');
    final manager = app.transfers!;
    expect(
      () => manager.upload(bytesInput([1]), '/私人'),
      throwsA(isA<DriveException>()),
    );
    manager.upload(bytesInput([1]), '/音乐/五月天');
    await settled(manager);
    expect(manager.tasks.single.status, TransferStatus.failed);
    await app.configureMusicRoot('/新音乐');
    methods.clear();
    manager.retry(manager.tasks.single);
    await settled(manager);
    expect(methods, isEmpty);
    expect(manager.tasks.single.error, contains('不在当前音乐目录内'));
  });

  test('scope comparison observes directory boundaries', () {
    expect(MusicDirectory.contains('/音乐', '/音乐/五月天'), isTrue);
    expect(MusicDirectory.contains('/音乐', '/音乐备份'), isFalse);
    expect(MusicDirectory.contains('/音乐', '/音乐/../私人'), isFalse);
    expect(MusicDirectory.contains(null, '/音乐'), isFalse);
  });

  test(
    'pagination stays in the opened directory and does not scan child folders',
    () async {
      final requested = <String>[];
      final app = await createApp(
        respond: (r) async {
          final dir = r.url.queryParameters['dir']!;
          final start = int.parse(r.url.queryParameters['start']!);
          requested.add('$dir:$start');
          return jsonResponse({
            'list': [
              if (start == 0)
                for (var i = 0; i < 200; i++)
                  {
                    'fs_id': i,
                    'server_filename': '歌手$i',
                    'path': '$dir/歌手$i',
                    'isdir': 1,
                  }
              else
                {
                  'fs_id': 201,
                  'server_filename': '摇滚',
                  'path': '$dir/摇滚',
                  'isdir': 1,
                },
            ],
          });
        },
      );
      await app.configureMusicRoot('/音乐');
      await app.browse('/音乐/五月天', more: true);
      expect(requested, ['/音乐:0']);
      await app.browse('/音乐', more: true);
      expect(requested, ['/音乐:0', '/音乐:200']);
      expect(app.entries.length, 201);
      expect(app.nextStart, isNull);
    },
  );

  test(
    'unavailable chosen folder shows error without falling back to drive root',
    () async {
      final requested = <String>[];
      final app = await createApp(
        respond: (r) async {
          requested.add(r.url.queryParameters['dir']!);
          return jsonResponse({'errno': -7});
        },
      );
      await app.configureMusicRoot('/没有权限的音乐');
      expect(requested, ['/没有权限的音乐']);
      expect(app.musicRoot, '/没有权限的音乐');
      expect(app.error, isNotNull);
      expect(app.busy, isFalse);
    },
  );
}
