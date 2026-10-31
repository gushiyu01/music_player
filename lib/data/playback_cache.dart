import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/drive_entry.dart';
import 'offline_library.dart';
import 'transfer_control.dart';

class CacheWrite {
  CacheWrite(this.entry, this.file, this.generation);
  final DriveEntry entry;
  final File file;
  final int generation;
  final control = TransferControl();
  final done = Completer<void>();
}

class PlaybackCache extends ChangeNotifier {
  PlaybackCache(
    Directory directory,
    SharedPreferences prefs, {
    this.maximumBytes = 1024 * 1024 * 1024,
  }) : storage = OfflineLibrary(
         directory,
         prefs,
         manifest: 'playback_cache_v1',
         includeSize: true,
       );

  final OfflineLibrary storage;
  final int maximumBytes;
  final _writes = <String, CacheWrite>{};
  final _protected = <String, int>{};
  Future<void>? _tail;
  int _generation = 0;
  bool _clearing = false;
  int get totalBytes => storage.totalBytes;
  List<DriveEntry> get entries => storage.entries;
  int get activeCount => _writes.length;
  Future<void>? pending(DriveEntry entry) =>
      _writes[storage.key(entry)]?.done.future;
  Future<void> initialize() => storage.initialize();
  String? localPath(DriveEntry entry) => storage.localPath(entry);

  Future<T> _serial<T>(Future<T> Function() work) async {
    final previous = _tail;
    final gate = Completer<void>();
    _tail = gate.future;
    if (previous != null) await previous;
    try {
      return await work();
    } finally {
      gate.complete();
    }
  }

  void protect(DriveEntry entry) {
    final key = storage.key(entry);
    _protected[key] = (_protected[key] ?? 0) + 1;
  }

  void release(DriveEntry entry) {
    final key = storage.key(entry);
    final count = (_protected[key] ?? 0) - 1;
    if (count <= 0) {
      _protected.remove(key);
    } else {
      _protected[key] = count;
    }
  }

  Future<void> touch(DriveEntry entry) => _serial(() => storage.touch(entry));

  Future<bool> _makeRoom(int bytes, {String? excluding}) async {
    var reserved = 0;
    for (final write in _writes.entries) {
      if (write.key != excluding) reserved += write.value.entry.size;
    }
    for (final entry in [...entries]) {
      if (totalBytes + reserved + bytes <= maximumBytes) break;
      if (_protected.containsKey(storage.key(entry))) continue;
      await storage.remove(entry);
    }
    return totalBytes + reserved + bytes <= maximumBytes;
  }

  Future<CacheWrite?> begin(DriveEntry entry) => _serial(() async {
    final key = storage.key(entry);
    if (_clearing ||
        !entry.isAudio ||
        entry.size > maximumBytes ||
        _writes.containsKey(key) ||
        localPath(entry) != null) {
      return null;
    }
    if (entries.any((e) => storage.key(e) == key)) await storage.remove(entry);
    if (!await _makeRoom(entry.size)) return null;
    final write = CacheWrite(entry, storage.fileFor(entry), _generation);
    _writes[key] = write;
    notifyListeners();
    return write;
  });

  Future<bool> complete(CacheWrite write, int bytes) => _serial(() async {
    var saved = false;
    try {
      final key = storage.key(write.entry);
      if (!write.control.cancelled &&
          write.generation == _generation &&
          identical(_writes[key], write) &&
          bytes > 0 &&
          (write.entry.size == 0 || bytes == write.entry.size) &&
          await _makeRoom(bytes, excluding: key)) {
        await storage.commitExisting(write.entry, bytes);
        saved = true;
      }
      return saved;
    } finally {
      try {
        if (!saved && await write.file.exists()) await write.file.delete();
      } finally {
        _writes.remove(storage.key(write.entry));
        if (!write.done.isCompleted) write.done.complete();
        notifyListeners();
      }
    }
  });

  Future<void> discard(CacheWrite write) async {
    write.control.cancel();
    await complete(write, 0);
  }

  Future<void> clear() async {
    if (_clearing) return;
    _clearing = true;
    _generation++;
    try {
      final writes = [..._writes.values];
      for (final write in writes) {
        write.control.cancel();
      }
      await Future.wait(writes.map((w) => w.done.future));
      await _serial(() async {
        for (final entry in [...entries]) {
          await storage.remove(entry);
        }
      });
    } finally {
      _clearing = false;
      notifyListeners();
    }
  }

  Future<void> cancel(DriveEntry entry) async {
    final write = _writes[storage.key(entry)];
    if (write != null) {
      write.control.cancel();
      await write.done.future;
    }
  }

  Future<void> remove(DriveEntry entry) async {
    await cancel(entry);
    await _serial(() => storage.remove(entry));
    notifyListeners();
  }

  Future<void> relocate(DriveEntry entry, DriveEntry replacement) async {
    await cancel(entry);
    await _serial(() => storage.relocate(entry, replacement));
    notifyListeners();
  }

  Future<bool> copyToDownload(DriveEntry entry, OfflineLibrary library) =>
      _serial(() async {
        final path = localPath(entry);
        if (path == null) return false;
        await File(path).copy(library.partialFor(entry).path);
        await library.commit(entry, File(path).lengthSync());
        if (!_protected.containsKey(storage.key(entry))) {
          await storage.remove(entry);
          notifyListeners();
        }
        return true;
      });

  @override
  void dispose() {
    for (final write in _writes.values) {
      write.control.cancel();
    }
    storage.dispose();
    super.dispose();
  }
}
