import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/baidu_client.dart';
import 'data/offline_library.dart';
import 'data/transfer_manager.dart';
import 'data/song_details_repository.dart';
import 'data/online_catalog.dart';
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
    this.details,
    this.catalog,
  }) {
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(savePlayback());
    });
    library?.addListener(_localChanged);
    transfers?.addListener(_transferChanged);
    transfers?.canUploadTo = containsDirectory;
    details?.canRead = (path) =>
        containsDirectory(path) && !_removedPaths.contains(path);
    details?.addListener(_localChanged);
    _mediaSubscription = audio.mediaItem.listen((item) {
      if (item == null ||
          audio.entries.isEmpty ||
          audio.index >= audio.entries.length) {
        return;
      }
      final entry = audio.entries[audio.index];
      if (_detailsEntry == '${entry.id}:${entry.path}') return;
      _detailsEntry = '${entry.id}:${entry.path}';
      if (details != null) {
        unawaited(
          details!.load(entry).catchError((_) => details!.cached(entry)),
        );
      }
    });
  }
  final BaiduClient client;
  final MusicHandler audio;
  final SharedPreferences prefs;
  final OfflineLibrary? library;
  final TransferManager? transfers;
  final SongDetailsRepository? details;
  final OnlineCatalog? catalog;
  StreamSubscription<dynamic>? _mediaSubscription;
  String? _detailsEntry;
  final Set<String> mutating = {};
  final Set<String> _removedPaths = {};
  String? operationNotice;
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
      details?.invalidatePending();
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

  bool canManage(DriveEntry entry) =>
      !entry.demo &&
      entry.isAudio &&
      containsDirectory(entry.path) &&
      !_removedPaths.contains(entry.path) &&
      !mutating.contains(entry.id);

  Future<DirectoryPage> listMusicFolders(String path, {int start = 0}) async {
    if (!containsDirectory(path)) {
      throw const DriveException('目标必须在指定音乐目录内', code: 'outside_root');
    }
    final page = await client.listDirectory(path, start: start);
    if (!containsDirectory(path)) {
      throw const DriveException('音乐目录已更改，请重新选择', code: 'outside_root');
    }
    return DirectoryPage(
      page.entries
          .where(
            (e) =>
                e.isDirectory && e.parent == path && containsDirectory(e.path),
          )
          .toList(),
      page.nextStart,
    );
  }

  Future<void> moveSong(DriveEntry entry, String destination) async {
    destination = MusicDirectory.normalize(destination);
    if (!containsDirectory(destination)) {
      throw const DriveException('目标必须在指定音乐目录内', code: 'outside_root');
    }
    await _mutate(entry, destination: destination);
  }

  Future<void> deleteSong(DriveEntry entry) => _mutate(entry);

  Future<void> _mutate(DriveEntry entry, {String? destination}) async {
    if (!canManage(entry)) {
      throw const DriveException('歌曲正在操作中或不在当前音乐目录内', code: 'unavailable');
    }
    if (transfers?.tasks.any(
          (t) => t.active && !t.uploading && t.entry?.id == entry.id,
        ) ==
        true) {
      throw const DriveException('请先完成或取消这首歌的下载任务', code: 'transfer_active');
    }
    mutating.add(entry.id);
    operationNotice = null;
    notifyListeners();
    try {
      // Stop only after the user has confirmed; a failure leaves all queue entries intact.
      final queued = audio.entries.any(
        (e) => e.id == entry.id && e.path == entry.path,
      );
      if (queued &&
          destination == null &&
          audio.entries[audio.index].id == entry.id) {
        await audio.pause();
      }
      if (destination == null) {
        await client.deleteSong(entry);
      } else {
        await client.moveSong(entry, destination);
      }
      transfers?.retire(entry);
      _removedPaths.add(entry.path);
      _browseGeneration++;
      busy = false;
      details?.invalidatePending();
      entries = entries.where((e) => e.path != entry.path).toList();
      if (destination == null) {
        if (queued) await audio.removeEntry(entry);
      } else {
        final replacement = DriveEntry(
          id: entry.id,
          name: entry.name,
          path: BaiduUpload.childPath(destination, entry.name),
          size: entry.size,
        );
        _removedPaths.remove(replacement.path);
        try {
          await library?.relocate(entry, replacement);
          await details?.move(entry, replacement);
        } catch (_) {
          operationNotice = '网盘移动成功，本地副本或资料目录更新失败；原本地下载仍可保留，请刷新检查';
        }
        if (queued) audio.replaceEntry(entry, replacement);
      }
      try {
        await savePlayback();
      } catch (_) {
        operationNotice = '网盘操作成功，本机播放进度保存失败，请刷新列表检查';
      }
    } finally {
      mutating.remove(entry.id);
      notifyListeners();
    }
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
          _removedPaths.remove(entry.path);
          transfers?.allow(entry);
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
    details?.invalidatePending();
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
    details?.removeListener(_localChanged);
    details?.canRead = null;
    unawaited(_mediaSubscription?.cancel());
    super.dispose();
  }
}
