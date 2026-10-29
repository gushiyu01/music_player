import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import 'app_controller.dart';
import 'data/baidu_client.dart';
import 'data/session_store.dart';
import 'data/offline_library.dart';
import 'data/transfer_manager.dart';
import 'data/song_details_repository.dart';
import 'data/online_catalog.dart';
import 'playback/music_handler.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final client = BaiduClient(SecureSessionStore());
    await client.initialize();
    final prefs = await SharedPreferences.getInstance();
    final support = await getApplicationSupportDirectory();
    final library = OfflineLibrary(
      Directory('${support.path}/offline_music'),
      prefs,
    );
    await library.initialize();
    final transfers = TransferManager(client, library);
    final details = SongDetailsRepository(
      Directory('${support.path}/song_details'),
      client,
      library: library,
    );
    await details.initialize();
    final handler = await AudioService.init<MusicHandler>(
      builder: () => MusicHandler(client, library: library, details: details),
      config: const AudioServiceConfig(
        androidNotificationChannelId:
            'io.github.gushiyu01.music_player.playback',
        androidNotificationChannelName: '云间音乐播放',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
        androidNotificationIcon: 'drawable/ic_notification',
      ),
    );
    await handler.configureSession();
    final controller = AppController(
      client,
      handler,
      prefs,
      library: library,
      transfers: transfers,
      details: details,
      catalog: OnlineCatalog(),
    );
    runApp(CloudMusicApp(controller: controller));
    await controller.initialize();
  } catch (_) {
    runApp(
      MaterialApp(
        theme: musicTheme,
        home: const Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('播放器初始化失败，请关闭应用后重试。若仍失败，请在 GitHub 提交设备型号和系统版本。'),
            ),
          ),
        ),
      ),
    );
  }
}

const canvasColor = Color(0xFF101411);
const surfaceColor = Color(0xFF1C231E);
const accentColor = Color(0xFFBDE7A2);
const mutedColor = Color(0xFF98A598);

final musicTheme = ThemeData(
  brightness: Brightness.dark,
  useMaterial3: true,
  scaffoldBackgroundColor: canvasColor,
  colorScheme: const ColorScheme.dark(
    primary: accentColor,
    surface: surfaceColor,
    onSurface: Color(0xFFE9EFE5),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: canvasColor,
    scrolledUnderElevation: 0,
  ),
  snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: surfaceColor,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide.none,
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
  ),
);

class CloudMusicApp extends StatelessWidget {
  const CloudMusicApp({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '云间',
    theme: musicTheme,
    debugShowCheckedModeBanner: false,
    home: HomeScreen(controller: controller),
  );
}
