import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/baidu_client.dart';
import 'models/drive_entry.dart';
import 'playback/music_handler.dart';

class AppController extends ChangeNotifier {
  AppController(this.client, this.audio, this.prefs) {
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(savePlayback());
    });
  }
  final BaiduClient client;
  final MusicHandler audio;
  final SharedPreferences prefs;
  late final Timer _timer;
  bool demo = true;
  bool busy = false;
  String directory = '/';
  String query = '';
  String? error;
  int? nextStart;
  int _browseGeneration = 0;
  List<DriveEntry> entries = [...demoTracks];
  Set<String> favorites = {};

  bool get connected => client.session.connected;
  List<DriveEntry> get visible =>
      entries
          .where(
            (entry) =>
                (entry.isDirectory || entry.isAudio) &&
                entry.name.toLowerCase().contains(query.toLowerCase()),
          )
          .toList()
        ..sort(
          (a, b) => a.isDirectory != b.isDirectory
              ? (a.isDirectory ? -1 : 1)
              : a.name.compareTo(b.name),
        );
  List<DriveEntry> get songs => visible.where((e) => e.isAudio).toList();

  Future<void> initialize() async {
    favorites = (prefs.getStringList('favorites') ?? []).toSet();
    directory = prefs.getString('directory') ?? '/';
    demo = !connected;
    try {
      final value =
          jsonDecode(prefs.getString('playback') ?? '{}')
              as Map<String, dynamic>;
      final tracks = (value['tracks'] as List? ?? [])
          .cast<Map<String, dynamic>>()
          .map(DriveEntry.fromJson)
          .where((e) => e.demo || connected)
          .toList();
      audio.restore(
        tracks,
        value['index'] as int? ?? 0,
        Duration(milliseconds: value['position'] as int? ?? 0),
      );
    } catch (_) {
      /* Corrupt local playback state must not prevent opening the app. */
    }
    if (connected) {
      await browse(directory);
    } else {
      notifyListeners();
    }
  }

  void search(String text) {
    query = text;
    notifyListeners();
  }

  Future<void> browse(String dir, {bool more = false}) async {
    if (more && (busy || nextStart == null)) return;
    final generation = ++_browseGeneration;
    demo = false;
    busy = true;
    error = null;
    if (!more) {
      directory = dir;
      query = '';
      entries = [];
      nextStart = null;
    }
    notifyListeners();
    try {
      final page = await client.listDirectory(
        dir,
        start: more ? nextStart! : 0,
      );
      if (generation != _browseGeneration) return;
      final unique = {for (final entry in entries) entry.id: entry};
      for (final entry in page.entries) {
        unique[entry.id] = entry;
      }
      entries = unique.values.toList();
      nextStart = page.nextStart;
      await prefs.setString('directory', directory);
    } catch (failure) {
      if (generation == _browseGeneration) {
        error = failure is DriveException ? failure.message : '目录加载失败，请重试';
      }
    } finally {
      if (generation == _browseGeneration) {
        busy = false;
        notifyListeners();
      }
    }
  }

  void useDemo() {
    _browseGeneration++;
    demo = true;
    directory = '/';
    entries = [...demoTracks];
    nextStart = null;
    query = '';
    error = null;
    busy = false;
    notifyListeners();
  }

  Future<void> toggleFavorite(DriveEntry entry) async {
    final key = '${entry.demo ? 'demo' : 'baidu'}:${entry.id}';
    if (!favorites.add(key)) favorites.remove(key);
    notifyListeners();
    await prefs.setStringList('favorites', favorites.toList());
  }

  bool isFavorite(DriveEntry entry) =>
      favorites.contains('${entry.demo ? 'demo' : 'baidu'}:${entry.id}');

  Future<void> savePlayback() async {
    await prefs.setString(
      'playback',
      jsonEncode({
        'tracks': audio.entries
            .take(500)
            .map((entry) => entry.toJson())
            .toList(),
        'index': audio.index,
        'position': audio.currentPosition.inMilliseconds,
      }),
    );
  }

  Future<void> disconnect() async {
    await audio.clear();
    await client.disconnect();
    await prefs.remove('playback');
    await prefs.remove('favorites');
    favorites.clear();
    await prefs.remove('directory');
    useDemo();
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }
}
