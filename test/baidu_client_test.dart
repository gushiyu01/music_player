import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music_player/data/baidu_client.dart';
import 'package:music_player/data/session_store.dart';
import 'package:music_player/models/drive_entry.dart';
import 'package:music_player/playback/baidu_audio_source.dart';

class MemoryStore implements SessionStore {
  MemoryStore([this.value = const DriveSession()]);
  DriveSession value;
  @override
  Future<DriveSession> read() async => value;
  @override
  Future<void> write(DriveSession session) async {
    value = session;
  }

  @override
  Future<void> clear() async {
    value = const DriveSession();
  }
}

class DelayedStore extends MemoryStore {
  final writing = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> write(DriveSession session) async {
    writing.complete();
    await release.future;
    await super.write(session);
  }
}

DriveSession credentials({int? expiresAt}) => DriveSession(
  appKey: 'test-key',
  secretKey: 'test-secret',
  accessToken: 'old-access',
  refreshToken: 'old-refresh',
  expiresAt: expiresAt ?? DateTime.now().millisecondsSinceEpoch + 86400000,
);
http.Response jsonResponse(Map<String, dynamic> value, [int status = 200]) =>
    http.Response(
      jsonEncode(value),
      status,
      headers: {'content-type': 'application/json'},
    );
const track = DriveEntry(id: '123', name: '歌曲.flac', path: '/音乐/歌曲.flac');

void main() {
  test('disconnect wins even when secure storage is still writing', () async {
    final store = DelayedStore();
    final client = BaiduClient(store);
    await client.initialize();
    final saving = client.replaceSession(credentials());
    await store.writing.future;
    final disconnecting = client.disconnect();
    store.release.complete();
    await Future.wait([saving, disconnecting]);
    expect(client.session.connected, isFalse);
    expect(store.value.connected, isFalse);
    client.client.close();
  });

  test(
    'cancelled device authorization cannot replace the current account',
    () async {
      final response = Completer<http.Response>();
      final requested = Completer<void>();
      final store = MemoryStore(credentials());
      final client = BaiduClient(
        store,
        client: MockClient((_) {
          requested.complete();
          return response.future;
        }),
      );
      await client.initialize();
      final completion = client.completeDevice(
        DeviceGrant(
          'device',
          'code',
          Uri.parse('https://openapi.baidu.com/device'),
          300,
          5,
        ),
        'another-key',
        'another-secret',
      );
      final checked = expectLater(
        completion,
        throwsA(
          isA<DriveException>().having((e) => e.code, 'code', 'cancelled'),
        ),
      );
      await requested.future;
      client.cancelPendingAuthorization();
      response.complete(jsonResponse({'access_token': 'cancelled-access'}));
      await checked;
      expect(client.session.accessToken, 'old-access');
      expect(store.value.accessToken, 'old-access');
    },
  );

  test(
    'temporary OAuth failures preserve existing tokens and report service error',
    () async {
      for (final status in [400, 503]) {
        final store = MemoryStore(credentials(expiresAt: 1));
        final client = BaiduClient(
          store,
          client: MockClient(
            (_) async => jsonResponse({'error': 'server_error'}, status),
          ),
        );
        await client.initialize();
        await expectLater(
          client.accessToken(),
          throwsA(
            isA<DriveException>().having(
              (e) => e.code,
              'code',
              status == 503 ? 'temporary' : 'server_error',
            ),
          ),
        );
        expect(store.value.accessToken, 'old-access');
        expect(store.value.refreshToken, 'old-refresh');
        expect(client.session.connected, isTrue);
      }
    },
  );

  test(
    'concurrent rejected-token refreshes share a single OAuth exchange',
    () async {
      var calls = 0;
      final client = BaiduClient(
        MemoryStore(credentials()),
        client: MockClient((request) async {
          calls++;
          expect(request.method, 'POST');
          expect(request.url.query, isEmpty);
          expect(
            Uri.splitQueryString(request.body)['grant_type'],
            'refresh_token',
          );
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return jsonResponse({
            'access_token': 'new-access',
            'refresh_token': 'new-refresh',
            'expires_in': 3600,
          });
        }),
      );
      await client.initialize();
      expect(
        await Future.wait(
          List.generate(
            5,
            (_) => client.accessToken(rejectedToken: 'old-access'),
          ),
        ),
        everyElement('new-access'),
      );
      expect(calls, 1);
      expect(
        await client.accessToken(rejectedToken: 'old-access'),
        'new-access',
      );
      expect(calls, 1);
    },
  );

  test(
    'disconnect during token refresh cannot resurrect authorization',
    () async {
      final response = Completer<http.Response>();
      final requested = Completer<void>();
      final store = MemoryStore(credentials(expiresAt: 1));
      final client = BaiduClient(
        store,
        client: MockClient((_) {
          requested.complete();
          return response.future;
        }),
      );
      await client.initialize();
      final refresh = client.accessToken();
      final check = expectLater(
        refresh,
        throwsA(
          isA<DriveException>().having((e) => e.code, 'code', 'cancelled'),
        ),
      );
      await requested.future;
      await client.disconnect();
      response.complete(
        jsonResponse({
          'access_token': 'stale',
          'refresh_token': 'stale-refresh',
        }),
      );
      await check;
      expect(client.session.connected, isFalse);
      expect(store.value.connected, isFalse);
    },
  );

  test(
    'device authorization pending does not erase the current connection',
    () async {
      final client = BaiduClient(
        MemoryStore(credentials()),
        client: MockClient(
          (_) async => jsonResponse({'error': 'authorization_pending'}, 400),
        ),
      );
      await client.initialize();
      await expectLater(
        client.completeDevice(
          DeviceGrant(
            'device',
            'code',
            Uri.parse('https://openapi.baidu.com/device'),
            300,
            5,
          ),
          'key',
          'secret',
        ),
        throwsA(
          isA<DriveException>().having(
            (e) => e.code,
            'code',
            'authorization_pending',
          ),
        ),
      );
      expect(client.session.accessToken, 'old-access');
    },
  );

  test(
    'directory pagination uses raw page size including non-audio files',
    () async {
      final starts = <String?>[];
      final client = BaiduClient(
        MemoryStore(credentials()),
        client: MockClient((request) async {
          expect(request.url.host, 'pan.baidu.com');
          expect(request.url.queryParameters['dir'], '/音乐');
          starts.add(request.url.queryParameters['start']);
          return jsonResponse({
            'errno': 0,
            'list': starts.length == 1
                ? [
                    {
                      'fs_id': 1,
                      'server_filename': '歌词.txt',
                      'path': '/音乐/歌词.txt',
                    },
                    {
                      'fs_id': 2,
                      'server_filename': '歌曲.flac',
                      'path': '/音乐/歌曲.flac',
                    },
                  ]
                : [],
          });
        }),
      );
      await client.initialize();
      final first = await client.listDirectory('/音乐', limit: 2);
      expect(first.nextStart, 2);
      expect(first.entries.where((e) => e.isAudio).length, 1);
      final second = await client.listDirectory(
        '/音乐',
        start: first.nextStart!,
        limit: 2,
      );
      expect(second.nextStart, isNull);
      expect(starts, ['0', '2']);
    },
  );

  test(
    'path permission errors remain errors instead of an empty successful scan',
    () async {
      final client = BaiduClient(
        MemoryStore(credentials()),
        client: MockClient((_) async => jsonResponse({'errno': -7})),
      );
      await client.initialize();
      await expectLater(
        client.listDirectory('/private'),
        throwsA(isA<DriveException>().having((e) => e.code, 'code', '-7')),
      );
    },
  );

  test(
    'auth rejection refreshes once and retries metadata using the new token',
    () async {
      final tokens = <String?>[];
      final client = BaiduClient(
        MemoryStore(credentials()),
        client: MockClient((request) async {
          if (request.url.host == 'openapi.baidu.com') {
            return jsonResponse({
              'access_token': 'new-access',
              'expires_in': 3600,
            });
          }
          tokens.add(request.url.queryParameters['access_token']);
          return tokens.length == 1
              ? jsonResponse({'errno': -6})
              : jsonResponse({'errno': 0, 'list': []});
        }),
      );
      await client.initialize();
      await client.listDirectory('/');
      expect(tokens, ['old-access', 'new-access']);
    },
  );

  test(
    'Range and User-Agent survive a trusted redirect, response length is retained',
    () async {
      final requests = <http.Request>[];
      final client = BaiduClient(
        MemoryStore(credentials()),
        client: MockClient((request) async {
          requests.add(request);
          if (request.url.host == 'pan.baidu.com') {
            return jsonResponse({
              'errno': 0,
              'list': [
                {'dlink': 'https://d.pcs.baidu.com/audio'},
              ],
            });
          }
          if (request.url.host == 'd.pcs.baidu.com') {
            return http.Response(
              '',
              302,
              headers: {'location': 'https://download.baidupcs.com/audio'},
            );
          }
          return http.Response(
            'abc',
            206,
            headers: {
              'content-range': 'bytes 10-12/100',
              'content-length': '3',
              'content-type': 'audio/flac',
            },
          );
        }),
      );
      await client.initialize();
      final result = await BaiduAudioSource(client, track).request(10, 13);
      expect(result.sourceLength, 100);
      expect(result.contentLength, 3);
      expect(result.offset, 10);
      expect(
        await result.stream.expand((bytes) => bytes).toList(),
        utf8.encode('abc'),
      );
      for (final request in requests.skip(1)) {
        expect(request.headers['Range'], 'bytes=10-12');
        expect(request.headers['User-Agent'], 'pan.baidu.com');
      }
      expect(requests[1].url.queryParameters['access_token'], 'old-access');
      expect(
        requests[2].url.queryParameters.containsKey('access_token'),
        isFalse,
      );
    },
  );

  test('untrusted redirects are blocked before a request is sent', () async {
    for (final target in [
      'https://127.0.0.1/audio',
      'https://baidu.com.evil.example/audio',
      'http://d.pcs.baidu.com/audio',
      'https://user@d.pcs.baidu.com/audio',
    ]) {
      var calls = 0;
      final client = BaiduClient(
        MemoryStore(credentials()),
        client: MockClient((request) async {
          calls++;
          if (request.url.host == 'pan.baidu.com') {
            return jsonResponse({
              'errno': 0,
              'list': [
                {'dlink': 'https://d.pcs.baidu.com/audio'},
              ],
            });
          }
          return http.Response('', 302, headers: {'location': target});
        }),
      );
      await client.initialize();
      await expectLater(
        client.openStream(track),
        throwsA(
          isA<DriveException>().having((e) => e.code, 'code', 'unsafe_link'),
        ),
      );
      expect(calls, 2);
    }
  });

  test(
    '403 renews the dlink once; 416, 429 and 500 keep their status',
    () async {
      var metas = 0;
      final client = BaiduClient(
        MemoryStore(credentials()),
        client: MockClient((request) async {
          if (request.url.host == 'pan.baidu.com') {
            metas++;
            return jsonResponse({
              'errno': 0,
              'list': [
                {'dlink': 'https://d.pcs.baidu.com/$metas'},
              ],
            });
          }
          return http.Response('abc', metas == 1 ? 403 : 200);
        }),
      );
      await client.initialize();
      final stream = await client.openStream(track);
      await stream.stream.drain<void>();
      expect(metas, 2);
      for (final status in [416, 429, 500]) {
        final api = BaiduClient(
          MemoryStore(credentials()),
          client: MockClient(
            (request) async => request.url.host == 'pan.baidu.com'
                ? jsonResponse({
                    'errno': 0,
                    'list': [
                      {'dlink': 'https://d.pcs.baidu.com/audio'},
                    ],
                  })
                : http.Response('', status),
          ),
        );
        await api.initialize();
        await expectLater(
          api.openStream(track),
          throwsA(
            isA<DriveException>().having((e) => e.status, 'status', status),
          ),
        );
      }
    },
  );

  test(
    'partial request answered with full body is never treated as the requested offset',
    () async {
      final client = BaiduClient(
        MemoryStore(credentials()),
        client: MockClient(
          (request) async => request.url.host == 'pan.baidu.com'
              ? jsonResponse({
                  'errno': 0,
                  'list': [
                    {'dlink': 'https://d.pcs.baidu.com/audio'},
                  ],
                })
              : http.Response('whole file', 200),
        ),
      );
      await client.initialize();
      await expectLater(
        client.openStream(track, start: 10),
        throwsA(
          isA<DriveException>().having((e) => e.code, 'code', 'range_ignored'),
        ),
      );
    },
  );
}
