import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_player/app_controller.dart';
import 'package:music_player/data/baidu_client.dart';
import 'package:music_player/data/session_store.dart';
import 'package:music_player/main.dart';
import 'package:music_player/models/drive_entry.dart';
import 'package:music_player/playback/music_handler.dart';

import 'baidu_client_test.dart' show MemoryStore;

class FakeMusicHandler extends BaseAudioHandler implements MusicHandler {
  @override
  final error = ValueNotifier<String?>(null);
  List<DriveEntry> selected = [];
  @override
  Future<void> playEntries(List<DriveEntry> tracks, int current) async {
    selected = tracks;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
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
