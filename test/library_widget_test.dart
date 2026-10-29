import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/testing.dart';
import 'package:music_player/app_controller.dart';
import 'package:music_player/data/baidu_client.dart';
import 'package:music_player/data/session_store.dart';
import 'package:music_player/main.dart';

import 'baidu_client_test.dart' show MemoryStore, credentials, jsonResponse;
import 'support/fake_music_handler.dart';

void main() {
  testWidgets(
    'real singer folders open their tracks and music root is remembered',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final requested = <String>[];
      final client = BaiduClient(
        MemoryStore(credentials()),
        client: MockClient((r) async {
          final directory = r.url.queryParameters['dir']!;
          requested.add(directory);
          return jsonResponse({
            'list': directory == '/音乐'
                ? [
                    for (final (index, name) in ['五月天', '许嵩', '周杰伦'].indexed)
                      {
                        'fs_id': index + 1,
                        'server_filename': name,
                        'path': '/音乐/$name',
                        'isdir': 1,
                      },
                  ]
                : [
                    {
                      'fs_id': 33,
                      'server_filename': '晴天.mp3',
                      'path': '$directory/晴天.mp3',
                    },
                  ],
          });
        }),
      );
      await client.initialize();
      final prefs = await SharedPreferences.getInstance();
      final app = AppController(client, FakeMusicHandler(), prefs);
      await app.configureMusicRoot('/音乐');
      await tester.pumpWidget(CloudMusicApp(controller: app));
      expect(find.text('五月天'), findsOneWidget);
      expect(find.text('许嵩'), findsOneWidget);
      expect(find.text('周杰伦'), findsOneWidget);
      expect(find.text('上传到此目录'), findsOneWidget);
      expect(find.byTooltip('返回上级目录'), findsNothing);
      expect(requested, ['/音乐']);
      await tester.tap(find.text('周杰伦'));
      await tester.pumpAndSettle();
      expect(find.text('晴天'), findsOneWidget);
      expect(requested.last, '/音乐/周杰伦');
      expect(find.byTooltip('返回上级目录'), findsOneWidget);
      await tester.tap(find.byTooltip('返回上级目录'));
      await tester.pumpAndSettle();
      expect(requested.last, '/音乐');
      expect(find.byTooltip('返回上级目录'), findsNothing);
      await tester.tap(find.text('音乐库'));
      await tester.pumpAndSettle();
      expect(requested.last, '/音乐');
      expect(prefs.getString('music_root'), '/音乐');
      await tester.tap(find.text('本地'));
      await tester.pumpAndSettle();
      expect(find.text('本地下载 / 按目录收藏'), findsOneWidget);
      expect(find.text('上传到此目录'), findsNothing);
      app.dispose();
    },
  );

  testWidgets(
    'root setup lists nothing until an explicit music path is saved',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        'music_root': '/',
        'directory': '/',
      });
      final requested = <String>[];
      final client = BaiduClient(
        MemoryStore(credentials()),
        client: MockClient((r) async {
          requested.add(r.url.queryParameters['dir']!);
          return jsonResponse({
            'list': [
              {
                'fs_id': 7,
                'server_filename': '摇滚',
                'path': '/音乐/摇滚',
                'isdir': 1,
              },
            ],
          });
        }),
      );
      await client.initialize();
      final app = AppController(
        client,
        FakeMusicHandler(),
        await SharedPreferences.getInstance(),
      );
      await app.initialize();
      await tester.pumpWidget(CloudMusicApp(controller: app));
      expect(requested, isEmpty);
      expect(find.text('先指定音乐目录'), findsOneWidget);
      expect(find.text('上传到此目录'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, '指定音乐目录'));
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byType(TextFormField),
                matching: find.byType(TextField),
              ),
            )
            .controller!
            .text,
        isEmpty,
      );
      await tester.enterText(find.byType(TextFormField), '/');
      await tester.tap(find.text('使用此目录'));
      await tester.pumpAndSettle();
      expect(find.textContaining('不能使用网盘根目录'), findsOneWidget);
      expect(requested, isEmpty);
      await tester.enterText(find.byType(TextFormField), '/音乐/');
      await tester.tap(find.text('使用此目录'));
      await tester.pumpAndSettle();
      expect(requested, ['/音乐']);
      expect(find.text('摇滚'), findsOneWidget);
      expect(find.text('分类 / 歌手目录'), findsOneWidget);
      expect(find.byTooltip('返回上级目录'), findsNothing);
      expect(find.text('上传到此目录'), findsOneWidget);
      await tester.tap(find.byTooltip('目录设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('更改音乐目录'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(requested, ['/音乐']);
      expect(app.musicRoot, '/音乐');
      app.dispose();
    },
  );

  testWidgets(
    'demo tracks filter by search, favorites persist, selected list becomes queue',
    (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final handler = FakeMusicHandler();
      final app = AppController(
        BaiduClient(MemoryStore(const DriveSession())),
        handler,
        await SharedPreferences.getInstance(),
      );
      await tester.pumpWidget(CloudMusicApp(controller: app));
      expect(find.text('云间'), findsOneWidget);
      expect(find.text('晨光 · Dawn'), findsOneWidget);
      await tester.tap(find.text('晨光 · Dawn'));
      expect(handler.selected.length, 2);
      await tester.tap(find.byTooltip('喜欢这首歌').first);
      await tester.pump();
      expect(app.favorites, contains('demo:demo-dawn'));
      await tester.enterText(find.byType(TextField), 'Tide');
      await tester.pump();
      expect(find.text('晨光 · Dawn'), findsNothing);
      expect(find.text('潮汐 · Tide'), findsOneWidget);
      await tester.tap(find.byTooltip('清除搜索'));
      await tester.pump();
      expect(find.text('晨光 · Dawn'), findsOneWidget);
      app.dispose();
    },
  );

  testWidgets(
    'connection screen explains direct access and accepts personal credentials',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final app = AppController(
        BaiduClient(MemoryStore()),
        FakeMusicHandler(),
        await SharedPreferences.getInstance(),
      );
      await tester.pumpWidget(CloudMusicApp(controller: app));
      await tester.tap(find.byTooltip('连接设置'));
      await tester.pumpAndSettle();
      expect(find.text('连接百度网盘'), findsOneWidget);
      expect(find.text('你的 AppKey'), findsOneWidget);
      expect(find.text('你的 SecretKey'), findsOneWidget);
      expect(find.textContaining('手机直连百度'), findsOneWidget);
      await tester.tap(find.text('在百度页面授权'));
      await tester.pump();
      expect(find.text('请填写自己的 AppKey 和 SecretKey'), findsOneWidget);
      app.dispose();
    },
  );
}
