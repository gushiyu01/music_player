import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:music_player/data/baidu_client.dart';
import 'package:music_player/models/drive_entry.dart';

import 'baidu_client_test.dart' show MemoryStore, credentials, jsonResponse;

const managedSong = DriveEntry(
  id: '7',
  name: '晴天.mp3',
  path: '/音乐/周杰伦/晴天.mp3',
  size: 3,
);

void main() {
  test(
    'move is synchronous, explicit no-overwrite and preserves filename',
    () async {
      final client = BaiduClient(
        MemoryStore(credentials()),
        client: MockClient((r) async {
          expect(r.method, 'POST');
          expect(r.url.queryParameters['method'], 'filemanager');
          expect(r.url.queryParameters['opera'], 'move');
          expect(r.bodyFields['async'], '0');
          expect(r.bodyFields['ondup'], 'fail');
          expect(jsonDecode(r.bodyFields['filelist']!), [
            {
              'path': managedSong.path,
              'dest': '/音乐/流行',
              'newname': '晴天.mp3',
              'ondup': 'fail',
            },
          ]);
          return jsonResponse({
            'errno': 0,
            'info': [
              {'errno': 0, 'path': managedSong.path},
            ],
          });
        }),
      );
      await client.initialize();
      await client.moveSong(managedSong, '/音乐/流行');
    },
  );

  test(
    'delete sends exactly the selected audio path, never siblings or directories',
    () async {
      final client = BaiduClient(
        MemoryStore(credentials()),
        client: MockClient((r) async {
          expect(r.url.queryParameters['opera'], 'delete');
          expect(jsonDecode(r.bodyFields['filelist']!), [managedSong.path]);
          expect(r.bodyFields['async'], '0');
          return jsonResponse({
            'info': [
              {'errno': 0, 'path': managedSong.path},
            ],
          });
        }),
      );
      await client.initialize();
      await client.deleteSong(managedSong);
      await expectLater(
        client.deleteSong(
          const DriveEntry(
            id: '9',
            name: '歌手',
            path: '/音乐/歌手',
            isDirectory: true,
          ),
        ),
        throwsA(isA<DriveException>()),
      );
    },
  );

  for (final response in [
    {
      'errno': 0,
      'info': [
        {'errno': -8},
      ],
    },
    {
      'errno': 0,
      'info': [
        {'errno': -9},
      ],
    },
    {'errno': 0, 'taskid': 123},
    {'errno': 0, 'info': []},
  ]) {
    test(
      'file-level failure or uncertain result $response is never treated as success',
      () async {
        final client = BaiduClient(
          MemoryStore(credentials()),
          client: MockClient((_) async => jsonResponse(response)),
        );
        await client.initialize();
        await expectLater(
          client.deleteSong(managedSong),
          throwsA(isA<DriveException>()),
        );
      },
    );
  }
}
