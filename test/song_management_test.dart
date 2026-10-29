import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_player/app_controller.dart';
import 'package:music_player/data/baidu_client.dart';
import 'package:music_player/data/offline_library.dart';
import 'package:music_player/main.dart';
import 'package:music_player/models/drive_entry.dart';
import 'package:music_player/ui/song_actions.dart';
import 'package:music_player/ui/song_details_screen.dart';

import 'baidu_client_test.dart' show MemoryStore, credentials, jsonResponse;
import 'baidu_file_actions_test.dart' show managedSong;
import 'support/fake_music_handler.dart';

Future<AppController> managedApp(
  Future<http.Response> Function(http.Request) respond, {
  OfflineLibrary? library,
}) async {
  if (library == null) SharedPreferences.setMockInitialValues({});
  final client = BaiduClient(
    MemoryStore(credentials()),
    client: MockClient(respond),
  );
  await client.initialize();
  final app = AppController(
    client,
    FakeMusicHandler(),
    await SharedPreferences.getInstance(),
    library: library,
  );
  await app.configureMusicRoot('/音乐');
  app.entries = [managedSong];
  app.directory = managedSong.parent;
  return app;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'move changes queue and local folder only after confirmed API success',
    () async {
      SharedPreferences.setMockInitialValues({});
      final temp = await Directory.systemTemp.createTemp('move-library-');
      final library = OfflineLibrary(
        temp,
        await SharedPreferences.getInstance(),
      );
      await library.initialize();
      await library.partialFor(managedSong).writeAsBytes([1, 2, 3]);
      await library.commit(managedSong, 3);
      final app = await managedApp(
        (r) async => r.url.queryParameters['method'] == 'list'
            ? jsonResponse({'list': []})
            : jsonResponse({
                'info': [
                  {'errno': 0},
                ],
              }),
        library: library,
      );
      await app.audio.playEntries([managedSong], 0);
      await app.moveSong(managedSong, '/音乐/流行');
      expect(app.audio.entries.single.path, '/音乐/流行/晴天.mp3');
      expect(library.entries.single.parent, '/音乐/流行');
      expect(library.localPath(library.entries.single), isNotNull);
      expect(app.entries, isEmpty);
      app.dispose();
      library.dispose();
      await temp.delete(recursive: true);
    },
  );
  test(
    'a listing started before deletion cannot resurrect a deleted song',
    () async {
      final pending = Completer<http.Response>();
      var delay = false;
      final app = await managedApp((r) async {
        if (r.url.queryParameters['method'] == 'filemanager') {
          return jsonResponse({
            'info': [
              {'errno': 0},
            ],
          });
        }
        if (delay) return pending.future;
        return jsonResponse({'list': []});
      });
      delay = true;
      final reading = app.browse(managedSong.parent);
      await Future<void>.delayed(Duration.zero);
      await app.deleteSong(managedSong);
      pending.complete(
        jsonResponse({
          'list': [managedSong.toJson()],
        }),
      );
      await reading;
      expect(app.entries, isEmpty);
      expect(app.canManage(managedSong), isFalse);
      expect(app.busy, isFalse);
      app.dispose();
    },
  );
  test(
    'deleting a cloud song keeps its local download and removes only that queued entry',
    () async {
      SharedPreferences.setMockInitialValues({});
      final temp = await Directory.systemTemp.createTemp('delete-library-');
      final library = OfflineLibrary(
        temp,
        await SharedPreferences.getInstance(),
      );
      await library.initialize();
      await library.partialFor(managedSong).writeAsBytes([1, 2, 3]);
      await library.commit(managedSong, 3);
      final app = await managedApp(
        (r) async => r.url.queryParameters['method'] == 'list'
            ? jsonResponse({'list': []})
            : jsonResponse({
                'info': [
                  {'errno': 0},
                ],
              }),
        library: library,
      );
      const other = DriveEntry(id: '99', name: '其他.mp3', path: '/音乐/其他.mp3');
      await app.audio.playEntries([other, managedSong], 0);
      await app.deleteSong(managedSong);
      expect(app.audio.entries.map((e) => e.id), ['99']);
      expect(library.localPath(managedSong), isNotNull);
      app.dispose();
      library.dispose();
      await temp.delete(recursive: true);
    },
  );
  test('failed move retains listing, queue and local metadata', () async {
    final app = await managedApp(
      (r) async => r.url.queryParameters['method'] == 'list'
          ? jsonResponse({'list': []})
          : jsonResponse({
              'info': [
                {'errno': -8},
              ],
            }),
    );
    await app.audio.playEntries([managedSong], 0);
    await expectLater(
      app.moveSong(managedSong, '/音乐/流行'),
      throwsA(isA<DriveException>()),
    );
    expect(app.entries.single.path, managedSong.path);
    expect(app.audio.entries.single.path, managedSong.path);
    expect(app.mutating, isEmpty);
    app.dispose();
  });
  test(
    'out of root source/target and directories never reach mutation API',
    () async {
      var requests = 0;
      final app = await managedApp((_) async {
        requests++;
        return jsonResponse({'list': []});
      });
      requests = 0;
      await expectLater(
        app.moveSong(managedSong, '/其他'),
        throwsA(isA<DriveException>()),
      );
      await expectLater(
        app.deleteSong(
          const DriveEntry(
            id: '8',
            name: '歌手',
            path: '/音乐/歌手',
            isDirectory: true,
          ),
        ),
        throwsA(isA<DriveException>()),
      );
      await expectLater(
        app.deleteSong(
          const DriveEntry(id: '9', name: '歌.mp3', path: '/其他/歌.mp3'),
        ),
        throwsA(isA<DriveException>()),
      );
      expect(requests, 0);
      app.dispose();
    },
  );
  testWidgets(
    'delete cancellation sends nothing; explicit confirmation deletes only selected song',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final operations = <String>[];
      final app = await managedApp((r) async {
        if (r.url.queryParameters['method'] == 'filemanager') {
          operations.add(r.url.queryParameters['opera']!);
        }
        return r.url.queryParameters['method'] == 'list'
            ? jsonResponse({'list': []})
            : jsonResponse({
                'info': [
                  {'errno': 0},
                ],
              });
      });
      await tester.pumpWidget(CloudMusicApp(controller: app));
      await tester.tap(find.byTooltip('歌曲操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除网盘文件'));
      await tester.pumpAndSettle();
      expect(find.text(managedSong.path), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(operations, isEmpty);
      expect(app.entries.length, 1);
      await tester.tap(find.byTooltip('歌曲操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除网盘文件'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除网盘文件'));
      await tester.pumpAndSettle();
      expect(operations, ['delete']);
      expect(app.entries, isEmpty);
      app.dispose();
    },
  );
  testWidgets(
    'move picker lists only selected folders and has no parent above music root',
    (tester) async {
      final requested = <String>[];
      final app = await managedApp((r) async {
        final dir = r.url.queryParameters['dir']!;
        requested.add(dir);
        return jsonResponse({
          'list': dir == '/音乐'
              ? [
                  {
                    'fs_id': 3,
                    'server_filename': '流行',
                    'path': '/音乐/流行',
                    'isdir': 1,
                  },
                ]
              : [],
        });
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: musicTheme,
          home: MoveDestinationScreen(controller: app, entry: managedSong),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('返回上级目录'), findsNothing);
      await tester.tap(find.text('流行'));
      await tester.pumpAndSettle();
      expect(requested, ['/音乐', '/音乐', '/音乐/流行']);
      expect(find.byTooltip('返回上级目录'), findsOneWidget);
      app.dispose();
    },
  );
  testWidgets('timed lyrics highlight and tapping a line seeks to its time', (
    tester,
  ) async {
    Duration? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: musicTheme,
        home: Scaffold(
          body: LyricsPanel(
            text: '[00:01]第一句\n[00:03]第二句',
            position: Stream.value(const Duration(seconds: 4)),
            onSeek: (value) => selected = value,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.text('第二句')).style!.color, accentColor);
    await tester.tap(find.text('第一句'));
    expect(selected, const Duration(seconds: 1));
  });
}
