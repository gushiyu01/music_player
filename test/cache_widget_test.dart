import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_player/app_controller.dart';
import 'package:music_player/data/offline_library.dart';
import 'package:music_player/data/playback_cache.dart';
import 'package:music_player/main.dart';

import 'playback_cache_test.dart' show cacheTrack, CacheClient;
import 'support/fake_music_handler.dart';

void main() {
  testWidgets(
    'cache appears locally and clear confirmation preserves manual downloads',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final directory = Directory.systemTemp.createTempSync('cache-ui-');
      final cache = PlaybackCache(Directory('${directory.path}/cache'), prefs);
      final library = OfflineLibrary(
        Directory('${directory.path}/download'),
        prefs,
      );
      final client = CacheClient();
      final cached = cacheTrack('听过的歌');
      final downloaded = cacheTrack('下载的歌');
      await tester.runAsync(() async {
        await cache.initialize();
        await library.initialize();
        final write = (await cache.begin(cached))!;
        await write.file.writeAsBytes([1, 2, 3, 4, 5, 6]);
        await cache.complete(write, 6);
        await library.partialFor(downloaded).writeAsBytes([1, 2, 3, 4, 5, 6]);
        await library.commit(downloaded, 6);
      });
      final audio = FakeMusicHandler();
      final app = AppController(
        client,
        audio,
        prefs,
        cache: cache,
        library: library,
      );
      await tester.pumpWidget(CloudMusicApp(controller: app));
      await tester.tap(find.text('本地'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('歌手'));
      await tester.pumpAndSettle();
      expect(find.text('听过的歌'), findsOneWidget);
      expect(find.text('下载的歌'), findsOneWidget);
      expect(find.textContaining('已缓存'), findsOneWidget);
      await tester.tap(find.byTooltip('歌曲缓存'));
      await tester.pumpAndSettle();
      expect(find.text('已缓存 1 首 · 上限 1 GB'), findsOneWidget);
      await tester.tap(find.text('清除歌曲缓存'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(cache.entries.length, 1);
      expect(audio.stopCalls, 0);
      await tester.tap(find.text('清除歌曲缓存'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('停止播放并清除'));
      for (var attempt = 0; attempt < 100; attempt++) {
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        });
        await tester.pumpAndSettle();
        if (find.text('歌曲缓存已清除，手动下载已保留').evaluate().isNotEmpty) break;
      }
      expect(cache.entries, isEmpty);
      expect(library.localPath(downloaded), isNotNull);
      expect(audio.stopCalls, 1);
      expect(find.text('已缓存 0 首 · 上限 1 GB'), findsOneWidget);
      expect(find.text('歌曲缓存已清除，手动下载已保留'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('听过的歌'), findsNothing);
      expect(find.text('下载的歌'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      app.dispose();
      cache.dispose();
      library.dispose();
      client.client.close();
      await tester.runAsync(() => directory.delete(recursive: true));
    },
  );
}
