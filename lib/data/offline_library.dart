import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/drive_entry.dart';

class OfflineRecord {
  const OfflineRecord(this.entry, this.bytes);
  final DriveEntry entry;
  final int bytes;
}

class OfflineLibrary extends ChangeNotifier {
  OfflineLibrary(this.directory, this.prefs);
  final Directory directory;
  final SharedPreferences prefs;
  final Map<String, OfflineRecord> _records = {};
  static const manifestKey = 'offline_music_v1';

  String key(DriveEntry entry) => sha256
      .convert(utf8.encode('${entry.demo}:${entry.id}:${entry.path}'))
      .toString();
  File fileFor(DriveEntry entry) => File.fromUri(
    directory.uri.resolve(
      '${key(entry)}.${entry.isAudio ? entry.extension : 'audio'}',
    ),
  );
  File partialFor(DriveEntry entry) => File('${fileFor(entry).path}.part');
  List<DriveEntry> get entries => _records.values.map((r) => r.entry).toList();
  int get totalBytes => _records.values.fold(0, (n, r) => n + r.bytes);

  String? localPath(DriveEntry entry) {
    final record = _records[key(entry)];
    if (record == null) return null;
    final file = fileFor(record.entry);
    try {
      return file.existsSync() && file.lengthSync() == record.bytes
          ? file.path
          : null;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> initialize() async {
    _records.clear();
    await directory.create(recursive: true);
    try {
      final raw = jsonDecode(prefs.getString(manifestKey) ?? '[]') as List;
      for (final value in raw) {
        try {
          final entry = DriveEntry.fromJson(
            Map<String, dynamic>.from(value['entry'] as Map),
          );
          final bytes = value['bytes'] as int;
          if (!entry.isAudio || bytes <= 0) continue;
          final file = fileFor(entry);
          if (await file.exists() && await file.length() == bytes) {
            _records[key(entry)] = OfflineRecord(entry, bytes);
          }
        } catch (_) {
          /* Skip an invalid local record, keep the rest. */
        }
      }
    } catch (_) {
      /* A corrupt manifest must not prevent starting the app. */
    }
    // This directory belongs exclusively to the app's offline library.
    final keep = _records.values
        .map((r) => fileFor(r.entry).absolute.path)
        .toSet();
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File && !keep.contains(entity.absolute.path)) {
        await entity.delete();
      }
    }
    await _persist();
    notifyListeners();
  }

  Future<void> commit(DriveEntry entry, int bytes) async {
    final partial = partialFor(entry);
    if (bytes <= 0 || await partial.length() != bytes) {
      throw const FileSystemException('Incomplete offline file');
    }
    await partial.rename(fileFor(entry).path);
    _records[key(entry)] = OfflineRecord(entry, bytes);
    try {
      await _persist();
    } catch (_) {
      _records.remove(key(entry));
      await fileFor(entry).delete();
      rethrow;
    }
    notifyListeners();
  }

  Future<void> remove(DriveEntry entry) async {
    final record = _records.remove(key(entry));
    if (record == null) return;
    try {
      await _persist();
    } catch (_) {
      _records[key(entry)] = record;
      rethrow;
    }
    final file = fileFor(entry);
    if (await file.exists()) await file.delete();
    notifyListeners();
  }

  Future<void> relocate(DriveEntry entry, DriveEntry replacement) async {
    final record = _records[key(entry)];
    if (record == null || localPath(entry) == null) return;
    final old = fileFor(entry);
    final target = fileFor(replacement);
    // Copy first so a failed manifest write leaves the original usable.
    await old.copy(target.path);
    _records[key(replacement)] = OfflineRecord(replacement, record.bytes);
    _records.remove(key(entry));
    try {
      await _persist();
    } catch (_) {
      _records.remove(key(replacement));
      _records[key(entry)] = record;
      await target.delete();
      rethrow;
    }
    await old.delete();
    notifyListeners();
  }

  Future<void> _persist() async {
    final ok = await prefs.setString(
      manifestKey,
      jsonEncode([
        for (final record in _records.values)
          {'entry': record.entry.toJson(), 'bytes': record.bytes},
      ]),
    );
    if (!ok) throw const FileSystemException('Unable to save offline manifest');
  }
}
