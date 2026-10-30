import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_player/app_controller.dart';
import 'package:music_player/data/online_catalog.dart';
import 'package:music_player/data/song_details_repository.dart';
import 'package:music_player/main.dart';
import 'package:music_player/models/catalog_query.dart';
import 'package:music_player/models/drive_entry.dart';
import 'package:music_player/models/song_details.dart';
import 'package:music_player/ui/player_screen.dart';
import 'package:music_player/ui/song_details_screen.dart';

import 'baidu_file_actions_test.dart' show managedSong;
import 'song_details_repository_test.dart' show DetailsClient;
import 'support/fake_music_handler.dart';

void main() {
  test(
    'search terms remove file noise and use singer rather than nested album directory',
    () {
      final terms = CatalogQuery.fromSong(
        const DriveEntry(
          id: '1',
          name: '01. 晴天【无损】.flac',
          path: '/音乐/周杰伦/叶惠美/01. 晴天【无损】.flac',
        ),
        const SongDetails(),
        '/音乐',
      );
      expect(terms.title, '晴天');
      expect(terms.artist, '周杰伦');
      final named = CatalogQuery.fromSong(
        const DriveEntry(
          id: '1',
          name: '02 - 许嵩 - 测试歌.mp3',
          path: '/音乐/流行/02 - 许嵩 - 测试歌.mp3',
        ),
        const SongDetails(),
        '/音乐',
      );
      expect(named.title, '测试歌');
      expect(named.artist, '许嵩');
    },
  );
  testWidgets(
    'player swipes between cover and timed lyrics with search-only upper-left menu',
    (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final directory = Directory.systemTemp.createTempSync('player-lyrics-');
      final client = DetailsClient();
      await client.initialize();
      final repo = SongDetailsRepository(directory, client);
      await tester.runAsync(() async {
        await repo.initialize();
        await repo.setLyrics(
          managedSong,
          '[00:00]原创第一行\n[00:03]原创第二行',
          'LRCLIB · 测试',
        );
      });
      final handler = FakeMusicHandler();
      await handler.playEntries([managedSong], 0);
      final app = AppController(
        client,
        handler,
        await SharedPreferences.getInstance(),
        details: repo,
        catalog: OnlineCatalog(),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: musicTheme,
          home: PlayerScreen(controller: app),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('原创第一行').hitTestable(), findsNothing);
      await tester.drag(
        find.byKey(const Key('player-pages')),
        const Offset(-340, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('原创第一行').hitTestable(), findsOneWidget);
      await tester.tap(find.text('原创第二行'));
      expect(handler.currentPosition, const Duration(seconds: 3));
      await tester.tap(find.byTooltip('搜索歌词或封面'));
      await tester.pumpAndSettle();
      expect(find.text('搜索歌词'), findsOneWidget);
      expect(find.text('搜索封面'), findsOneWidget);
      expect(find.text('导入歌词'), findsNothing);
      expect(find.text('导入封面'), findsNothing);
      final search = tester.getTopLeft(find.byTooltip('搜索歌词或封面'));
      expect(search.dx, lessThan(60));
      await tester.pumpWidget(const SizedBox.shrink());
      app.dispose();
      repo.dispose();
      await tester.runAsync(() => directory.delete(recursive: true));
    },
  );
  testWidgets(
    'failed artwork application retains candidates and permits selecting again',
    (tester) async {
      var attempts = 0;
      final catalog = OnlineCatalog(
        requestGap: Duration.zero,
        client: MockClient(
          (_) async => http.Response(
            '{"recordings":[{"title":"测试歌","releases":[{"id":"12345678-1234-1234-1234-123456789012","title":"测试专辑"}]}]}',
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      await tester.runAsync(() => catalog.covers('测试歌', ''));
      await tester.pumpWidget(
        MaterialApp(
          theme: musicTheme,
          home: CatalogSearchScreen(
            catalog: catalog,
            cover: true,
            title: '测试歌',
            artist: '',
            onApply: (_) async {
              attempts++;
              throw const CatalogException(
                '这个版本暂无封面，请选择其他候选',
                code: 'not_found',
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('搜索候选'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('异常'),
        findsNothing,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .join(' | '),
      );
      await tester.scrollUntilVisible(
        find.byType(ListTile),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.byType(ListTile));
      await tester.tap(find.byType(ListTile));
      await tester.pumpAndSettle();
      expect(find.text('测试歌'), findsWidgets);
      expect(find.textContaining('这个版本暂无封面'), findsOneWidget);
      await tester.ensureVisible(find.byType(ListTile));
      await tester.tap(find.byType(ListTile));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      catalog.dispose();
    },
  );
}
