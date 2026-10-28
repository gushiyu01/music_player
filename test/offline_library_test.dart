import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_player/data/offline_library.dart';
import 'package:music_player/models/drive_entry.dart';

const offlineTrack = DriveEntry(
  id: '123',
  name: '晴天.mp3',
  path: '/音乐/周杰伦/晴天.mp3',
  size: 3,
);

void main() {
  late Directory directory;
  late SharedPreferences prefs;
  late OfflineLibrary library;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    directory = await Directory.systemTemp.createTemp('cloud-music-test-');
    library = OfflineLibrary(directory, prefs);
    await library.initialize();
  });
  tearDown(() async {
    library.dispose();
    await directory.delete(recursive: true);
  });

  test(
    'only a complete committed file survives restart and can play without tokens',
    () async {
      await library.partialFor(offlineTrack).writeAsBytes([1, 2, 3]);
      expect(library.localPath(offlineTrack), isNull);
      await library.commit(offlineTrack, 3);
      final restored = OfflineLibrary(directory, prefs);
      await restored.initialize();
      expect(restored.entries.single.name, '晴天.mp3');
      expect(File(restored.localPath(offlineTrack)!).readAsBytesSync(), [
        1,
        2,
        3,
      ]);
      expect(restored.totalBytes, 3);
      expect(
        prefs.getString(OfflineLibrary.manifestKey),
        isNot(contains(directory.path)),
      );
      restored.dispose();
    },
  );

  test(
    'restart removes partial and orphan files, rejects truncated completed files',
    () async {
      await library.partialFor(offlineTrack).writeAsBytes([1, 2, 3]);
      await library.commit(offlineTrack, 3);
      await library.fileFor(offlineTrack).writeAsBytes([1]);
      await File('${directory.path}/orphan.part').writeAsBytes([1]);
      final restored = OfflineLibrary(directory, prefs);
      await restored.initialize();
      expect(restored.entries, isEmpty);
      expect(await directory.list().toList(), isEmpty);
      restored.dispose();
    },
  );

  test(
    'untrusted remote paths cannot choose an arbitrary local destination',
    () async {
      const entry = DriveEntry(
        id: '../../x',
        name: 'evil.mp3',
        path: '/../../outside',
      );
      expect(library.fileFor(entry).parent.path, directory.path);
      expect(
        library.fileFor(entry).uri.pathSegments.last,
        matches(r'^[a-f0-9]{64}\.mp3$'),
      );
    },
  );

  test(
    'bad manifest does not crash startup and removing a download preserves remote metadata',
    () async {
      await prefs.setString(
        OfflineLibrary.manifestKey,
        jsonEncode([
          {'entry': null},
        ]),
      );
      await library.initialize();
      await library.partialFor(offlineTrack).writeAsBytes([1, 2, 3]);
      await library.commit(offlineTrack, 3);
      await library.remove(offlineTrack);
      expect(library.entries, isEmpty);
      expect(await library.fileFor(offlineTrack).exists(), isFalse);
      expect(offlineTrack.path, '/音乐/周杰伦/晴天.mp3');
    },
  );
}
