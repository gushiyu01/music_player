import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_player/data/baidu_client.dart';
import 'package:music_player/data/offline_library.dart';
import 'package:music_player/data/transfer_control.dart';
import 'package:music_player/data/transfer_manager.dart';
import 'package:music_player/models/drive_entry.dart';

import 'baidu_client_test.dart' show MemoryStore, credentials, jsonResponse;
import 'offline_library_test.dart' show offlineTrack;

class MemoryAssets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(Uint8List.fromList([1, 2, 3]));
}

Future<void> settled(TransferManager manager) async {
  if (manager.activeCount == 0) return;
  final done = Completer<void>();
  void check() {
    if (manager.activeCount == 0 && !done.isCompleted) done.complete();
  }

  manager.addListener(check);
  try {
    await done.future.timeout(const Duration(seconds: 8));
  } finally {
    manager.removeListener(check);
  }
}

UploadInput bytesInput(List<int> bytes, {String name = '歌曲.mp3'}) =>
    UploadInput(
      name: name,
      size: bytes.length,
      read: (start, end) => Stream.value(bytes.sublist(start, end)),
    );

void main() {
  test(
    'upload hashes bounded parts, sends sequential multipart slices and uses no-overwrite create',
    () async {
      final bytes = List<int>.filled(BaiduUpload.blockSize + 3, 97);
      final hashes = [
        md5.convert(bytes.sublist(0, BaiduUpload.blockSize)).toString(),
        md5.convert([97, 97, 97]).toString(),
      ];
      final steps = <String>[];
      final client = BaiduClient(
        MemoryStore(credentials()),
        client: MockClient((r) async {
          final method = r.url.queryParameters['method']!;
          steps.add(method);
          if (method == 'upload') {
            expect(r.url.host, 'd.pcs.baidu.com');
            expect(r.followRedirects, isFalse);
            expect(
              r.headers['content-type'],
              startsWith('multipart/form-data'),
            );
            final part = int.parse(r.url.queryParameters['partseq']!);
            expect(part, steps.where((e) => e == 'upload').length - 1);
            expect(r.body, contains('name="file"'));
            return jsonResponse({'md5': hashes[part]});
          }
          expect(r.method, 'POST');
          expect(r.bodyFields['path'], '/音乐/五月天/歌曲.mp3');
          expect(r.bodyFields['rtype'], '0');
          expect(jsonDecode(r.bodyFields['block_list']!), hashes);
          if (method == 'precreate') {
            return jsonResponse({
              'uploadid': 'u1',
              'return_type': 1,
              'block_list': [0, 1],
            });
          }
          expect(r.bodyFields['uploadid'], 'u1');
          return jsonResponse({'fs_id': 33, 'path': '/音乐/五月天/歌曲.mp3'});
        }),
      );
      await client.initialize();
      final result = await client.uploadFile(
        bytesInput(bytes),
        '/音乐/五月天',
        control: TransferControl(),
        onProgress: (_, _) {},
      );
      expect(result.id, '33');
      expect(steps, ['precreate', 'upload', 'upload', 'create']);
    },
  );

  for (final scenario in [
    'checksum',
    'collision',
    'cancel',
    'invalid_part',
    'short_read',
  ]) {
    test('upload $scenario never commits a remote file', () async {
      final control = TransferControl();
      final steps = <String>[];
      final client = BaiduClient(
        MemoryStore(credentials()),
        client: MockClient((r) async {
          final method = r.url.queryParameters['method']!;
          steps.add(method);
          if (method == 'precreate') {
            if (scenario == 'collision') return jsonResponse({'errno': -8});
            return jsonResponse({
              'uploadid': 'u',
              'block_list': scenario == 'invalid_part' ? [8] : [0],
            });
          }
          return jsonResponse({
            'md5': scenario == 'checksum'
                ? 'bad'
                : md5.convert([1, 2, 3]).toString(),
          });
        }),
      );
      await client.initialize();
      final input = scenario == 'short_read'
          ? UploadInput(
              name: 'x.mp3',
              size: 3,
              read: (_, _) => Stream.value([1]),
            )
          : bytesInput([1, 2, 3]);
      await expectLater(
        client.uploadFile(
          input,
          '/音乐',
          control: control,
          onProgress: (_, phase) {
            if (scenario == 'cancel' && phase == '保存到网盘') control.cancel();
          },
        ),
        throwsA(isA<DriveException>()),
      );
      expect(steps, isNot(contains('create')));
      expect(client.session.connected, isTrue);
    });
  }

  test(
    'invalid paths are rejected and folder creation does not overwrite',
    () async {
      for (final name in ['../file.mp3', 'a/b.mp3', 'a\\b.mp3', '', '..']) {
        expect(
          () => BaiduUpload.childPath('/音乐', name),
          throwsA(isA<DriveException>()),
        );
      }
      final client = BaiduClient(
        MemoryStore(credentials()),
        client: MockClient((r) async {
          expect(r.bodyFields, {
            'path': '/音乐/许嵩',
            'size': '0',
            'isdir': '1',
            'rtype': '0',
          });
          return jsonResponse({'errno': 0});
        }),
      );
      await client.initialize();
      await client.createFolder('/音乐', '许嵩');
    },
  );

  group('download queue', () {
    late Directory directory;
    late OfflineLibrary library;
    late TransferManager manager;
    late BaiduClient client;
    var fail = false;
    setUp(() async {
      fail = false;
      SharedPreferences.setMockInitialValues({});
      directory = await Directory.systemTemp.createTemp('music-download-test-');
      library = OfflineLibrary(
        directory,
        await SharedPreferences.getInstance(),
      );
      await library.initialize();
      client = BaiduClient(
        MemoryStore(credentials()),
        client: MockClient((r) async {
          if (r.url.host == 'pan.baidu.com') {
            return jsonResponse({
              'list': [
                {'dlink': 'https://d.pcs.baidu.com/audio'},
              ],
            });
          }
          return http.Response.bytes(
            fail ? [1] : [1, 2, 3],
            200,
            headers: {'content-type': 'audio/mpeg'},
          );
        }),
      );
      await client.initialize();
      manager = TransferManager(client, library, assets: MemoryAssets());
    });
    tearDown(() async {
      manager.dispose();
      library.dispose();
      await directory.delete(recursive: true);
    });

    test(
      'download persists, duplicates coalesce, deletion permits downloading again',
      () async {
        manager.download(offlineTrack);
        manager.download(offlineTrack);
        await settled(manager);
        expect(manager.tasks.length, 1);
        expect(manager.tasks.single.status, TransferStatus.done);
        expect(library.localPath(offlineTrack), isNotNull);
        await library.remove(offlineTrack);
        manager.download(offlineTrack);
        await settled(manager);
        expect(manager.tasks.length, 2);
        expect(library.localPath(offlineTrack), isNotNull);
      },
    );

    test(
      'incomplete downloads stay out of library, delete partials and allow retry',
      () async {
        fail = true;
        manager.download(offlineTrack);
        await settled(manager);
        expect(manager.tasks.single.status, TransferStatus.failed);
        expect(library.entries, isEmpty);
        expect(await directory.list().toList(), isEmpty);
        fail = false;
        manager.retry(manager.tasks.single);
        await settled(manager);
        expect(manager.tasks.single.status, TransferStatus.done);
      },
    );

    test(
      'cancelling an active download never leaves a playable partial file',
      () async {
        manager.addListener(() {
          if (manager.tasks.isNotEmpty) {
            final task = manager.tasks.first;
            if (task.bytes > 0 && task.active && !task.control.cancelled) {
              manager.cancel(task);
            }
          }
        });
        manager.download(offlineTrack);
        await settled(manager);
        expect(manager.tasks.single.status, TransferStatus.cancelled);
        expect(library.entries, isEmpty);
        expect(await directory.list().toList(), isEmpty);
      },
    );

    test(
      'cancelled queued transfers do not write a file; demo uses persistent disk library',
      () async {
        manager.download(demoTracks[0]);
        manager.download(demoTracks[1]);
        manager.cancel(manager.tasks.last);
        await settled(manager);
        expect(manager.tasks.last.status, TransferStatus.cancelled);
        expect(library.entries.map((e) => e.id), [demoTracks[0].id]);
        expect(File(library.localPath(demoTracks[0])!).readAsBytesSync(), [
          1,
          2,
          3,
        ]);
      },
    );
  });
}
