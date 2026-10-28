import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/testing.dart';
import 'package:music_player/app_controller.dart';
import 'package:music_player/data/baidu_client.dart';
import 'package:music_player/data/session_store.dart';
import 'package:music_player/main.dart';
import 'package:music_player/models/drive_entry.dart';
import 'package:music_player/playback/music_handler.dart';

import 'baidu_client_test.dart' show MemoryStore, credentials, jsonResponse;

class FakeMusicHandler extends BaseAudioHandler implements MusicHandler {
  @override
  final error = ValueNotifier<String?>(null);
  List<DriveEntry> selected = [];
  @override
  List<DriveEntry> get entries => selected;
  @override
  int index = 0;
  @override
  Duration get currentPosition => Duration.zero;
  @override
  Future<void> clear() async {
    selected = [];
  }

  @override
  Future<void> playEntries(
    List<DriveEntry> tracks,
    int current, {
    bool onlineOnly = false,
  }) async {
    selected = tracks;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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
      await app.browse('/音乐');
      await app.setMusicRoot();
      await tester.pumpWidget(CloudMusicApp(controller: app));
      expect(find.text('五月天'), findsOneWidget);
      expect(find.text('许嵩'), findsOneWidget);
      expect(find.text('周杰伦'), findsOneWidget);
      expect(find.text('上传到此目录'), findsOneWidget);
      await tester.tap(find.text('周杰伦'));
      await tester.pumpAndSettle();
      expect(find.text('晴天'), findsOneWidget);
      expect(requested.last, '/音乐/周杰伦');
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
