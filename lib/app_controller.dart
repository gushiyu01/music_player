import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/baidu_client.dart';
import 'data/offline_library.dart';
import 'data/transfer_manager.dart';
import 'models/drive_entry.dart';
import 'models/music_directory.dart';
import 'playback/music_handler.dart';

class AppController extends ChangeNotifier {
  AppController(
    this.client,
    this.audio,
    this.prefs, {
    this.library,
    this.transfers,
  }) {
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(savePlayback());
    });
    library?.addListener(_localChanged);
    transfers?.addListener(_transferChanged);
    transfers?.canUploadTo = containsDirectory;
  }
  final BaiduClient client;
  final MusicHandler audio;
  final SharedPreferences prefs;
  final OfflineLibrary? library;
  final TransferManager? transfers;
  final Set<MusicTransfer> _observedUploads = {};
  bool local = false;
  String? localDirectory;
  String? musicRoot;
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
  bool get needsMusicRoot => connected && musicRoot == null;
  bool get browsingMusic => !local && !demo && musicRoot != null;
  bool get canGoUp => browsingMusic && directory != musicRoot;
  bool containsDirectory(String path) =>
      connected && MusicDirectory.contains(musicRoot, path);
  List<DriveEntry> get visible =>
      (local ? _localEntries : entries)
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

  List<DriveEntry> get _localEntries {
    final saved = library?.entries ?? <DriveEntry>[];
    if (localDirectory != null) {
      return saved.where((e) => e.parent == localDirectory).toList();
    }
    final parents = saved.map((e) => e.parent).toSet();
    return [
      for (final parent in parents)
        DriveEntry(
          id: 'local:$parent',
          name: parent == '/'
              ? '根目录音乐'
              : parent == 'assets/audio'
              ? '原创试听'
              : parent.split('/').last,
          path: parent,
          isDirectory: true,
        ),
    ];
  }

  void _localChanged() => notifyListeners();
  void _transferChanged() {
    for (final task in transfers?.tasks ?? <MusicTransfer>[]) {
      if (task.uploading &&
          task.status == TransferStatus.done &&
          _observedUploads.add(task)) {
        if (!local && !demo && task.destination == directory) {
          unawaited(browse(directory));
        }
      }
    }
    notifyListeners();
  }

  void showLocal([String? folder]) {
    _browseGeneration++;
    local = true;
    localDirectory = folder;
    query = '';
    busy = false;
    error = null;
    notifyListeners();
  }

  Future<void> configureMusicRoot(String input) async {
    final root = MusicDirectory.normalize(input);
    if (!connected) {
      throw const DriveException('请先连接百度网盘', code: 'not_connected');
    }
    if (musicRoot != root) {
      musicRoot = root;
      _browseGeneration++;
      // A queued upload must never silently continue into the previous library.
      for (final task in transfers?.tasks ?? <MusicTransfer>[]) {
        if (task.uploading && !containsDirectory(task.destination)) {
          transfers?.cancel(task);
        }
      }
    }
    await prefs.setString('music_root', root);
    if (musicRoot == root) await browse(root);
  }

  void showRootSetup() {
    _browseGeneration++;
    local = false;
    demo = false;
    directory = '';
    entries = [];
    nextStart = null;
    query = '';
    error = null;
    busy = false;
    notifyListeners();
  }

  Future<void> createFolder(String destination, String name) async {
    if (!containsDirectory(destination)) {
      throw const DriveException('只能在指定音乐目录内新建文件夹', code: 'outside_root');
    }
    await client.createFolder(destination, name);
  }

  Future<void> openLibrary() async {
    if (connected) {
      if (musicRoot == null) {
        showRootSetup();
      } else {
        await browse(musicRoot!);
      }
    } else {
      useDemo();
    }
  }

  Future<void> initialize() async {
    favorites = (prefs.getStringList('favorites') ?? []).toSet();
    try {
      musicRoot = MusicDirectory.normalize(prefs.getString('music_root') ?? '');
    } on DriveException {
      musicRoot = null;
      await prefs.remove('music_root');
      await prefs.remove('directory');
    }
    final previous = prefs.getString('directory') ?? '';
    directory = containsDirectory(previous)
        ? MusicDirectory.normalize(previous)
        : musicRoot ?? '';
    demo = !connected;
    try {
      final value =
          jsonDecode(prefs.getString('playback') ?? '{}')
              as Map<String, dynamic>;
      final tracks = (value['tracks'] as List? ?? [])
          .cast<Map<String, dynamic>>()
          .map(DriveEntry.fromJson)
          .where(
            (e) =>
                e.demo ||
                containsDirectory(e.path) ||
                library?.localPath(e) != null,
          )
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
      if (musicRoot == null) {
        showRootSetup();
      } else {
        await browse(directory);
      }
    } else {
      notifyListeners();
    }
  }

  void search(String text) {
    query = text;
    notifyListeners();
  }

  Future<void> browse(String dir, {bool more = false}) async {
    if (!containsDirectory(dir)) {
      error = musicRoot == null ? '请先指定音乐目录' : '只能浏览指定音乐目录及其子目录';
      notifyListeners();
      return;
    }
    dir = MusicDirectory.normalize(dir);
    if (more && dir != directory) return;
    if (more && (busy || nextStart == null)) return;
    final generation = ++_browseGeneration;
    local = false;
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
        if (containsDirectory(entry.path) && entry.parent == dir) {
          unique[entry.id] = entry;
        }
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
    local = false;
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
    transfers?.cancelAll();
    await audio.clear();
    await client.disconnect();
    await prefs.remove('playback');
    await prefs.remove('favorites');
    favorites.clear();
    await prefs.remove('directory');
    await prefs.remove('music_root');
    musicRoot = null;
    useDemo();
  }

  @override
  void dispose() {
    _timer.cancel();
    library?.removeListener(_localChanged);
    transfers?.removeListener(_transferChanged);
    transfers?.canUploadTo = null;
    super.dispose();
  }
}
