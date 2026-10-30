import 'dart:convert';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music_player/data/baidu_client.dart';
import 'package:music_player/data/online_catalog.dart';

void main() {
  test(
    'lyrics search sends only user-entered title and artist with identified client',
    () async {
      final catalog = OnlineCatalog(
        client: MockClient((r) async {
          expect(r.url.host, 'lrclib.net');
          expect(r.url.queryParameters, {
            'track_name': '晴天',
            'artist_name': '周杰伦',
          });
          expect(r.headers['User-Agent'], contains('YunjianMusic'));
          expect(r.headers.containsKey('Authorization'), isFalse);
          expect(r.url.toString(), isNot(contains('access_token')));
          return http.Response(
            jsonEncode([
              {
                'id': 1,
                'trackName': '晴天',
                'artistName': '周杰伦',
                'albumName': '测试专辑',
                'duration': 269,
                'syncedLyrics': '[00:01]测试',
              },
              {'id': 2, 'syncedLyrics': '', 'plainLyrics': '纯文本歌词'},
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final results = await catalog.lyrics('晴天', '周杰伦');
      expect(results.first.lyrics, '[00:01]测试');
      expect(results.last.lyrics, '纯文本歌词');
      catalog.dispose();
    },
  );
  test('Retry-After prevents immediate retries against catalog', () async {
    var requests = 0;
    final catalog = OnlineCatalog(
      client: MockClient((_) async {
        requests++;
        return http.Response('', 429, headers: {'retry-after': '60'});
      }),
    );
    await expectLater(
      catalog.lyrics('测试', '测试'),
      throwsA(isA<DriveException>()),
    );
    await expectLater(
      catalog.lyrics('测试', '测试'),
      throwsA(isA<DriveException>()),
    );
    expect(requests, 1);
    catalog.dispose();
  });
  test(
    'MusicBrainz release candidates are explicit and invalid IDs excluded',
    () async {
      final catalog = OnlineCatalog(
        client: MockClient((r) async {
          expect(r.url.host, 'musicbrainz.org');
          return http.Response(
            jsonEncode({
              'recordings': [
                {
                  'title': '晴天',
                  'artist-credit': [
                    {'name': '周杰伦'},
                  ],
                  'length': 269000,
                  'releases': [
                    {
                      'id': '12345678-1234-1234-1234-123456789012',
                      'title': '测试专辑',
                    },
                    {'id': '../bad', 'title': '忽略'},
                  ],
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final results = await catalog.covers('晴天', '周杰伦');
      expect(results.single.album, '测试专辑');
      expect(results.single.duration, 269);
      catalog.dispose();
    },
  );
  test(
    'cover redirect outside archive domains is blocked before request',
    () async {
      final hosts = <String>[];
      final catalog = OnlineCatalog(
        client: MockClient((r) async {
          hosts.add(r.url.host);
          return http.Response(
            '',
            307,
            headers: {'location': 'https://127.0.0.1/private'},
          );
        }),
      );
      await expectLater(
        catalog.coverBytes(
          const CatalogResult(
            id: '12345678-1234-1234-1234-123456789012',
            title: 'test',
            artist: 'artist',
            album: 'album',
          ),
        ),
        throwsFormatException,
      );
      expect(hosts, ['coverartarchive.org']);
      catalog.dispose();
    },
  );
  test(
    'a temporary HTTP failure retries once and successful searches are cached',
    () async {
      var calls = 0;
      final catalog = OnlineCatalog(
        requestGap: Duration.zero,
        client: MockClient((_) async {
          calls++;
          if (calls == 1) return http.Response('', 502);
          return http.Response(
            jsonEncode([
              {'id': 1, 'syncedLyrics': '[00:01]original'},
            ]),
            200,
          );
        }),
      );
      expect((await catalog.lyrics('测试', '')).length, 1);
      await catalog.lyrics('测试', '');
      expect(calls, 2);
      catalog.dispose();
    },
  );
  test('timed out searches retry once with a specific network error', () async {
    var calls = 0;
    final catalog = OnlineCatalog(
      requestGap: Duration.zero,
      client: MockClient((_) async {
        calls++;
        throw TimeoutException('offline');
      }),
    );
    await expectLater(
      catalog.lyrics('测试', ''),
      throwsA(isA<CatalogException>().having((e) => e.code, 'code', 'network')),
    );
    expect(calls, 2);
    catalog.dispose();
  });
  test(
    'lyrics limits do not block cover search and are not bypassed',
    () async {
      final hosts = <String>[];
      final catalog = OnlineCatalog(
        client: MockClient((request) async {
          hosts.add(request.url.host);
          return request.url.host == 'lrclib.net'
              ? http.Response('', 429, headers: {'retry-after': '60'})
              : http.Response('{"recordings":[]}', 200);
        }),
      );
      await expectLater(
        catalog.lyrics('测试', ''),
        throwsA(isA<CatalogException>()),
      );
      await expectLater(
        catalog.lyrics('测试2', ''),
        throwsA(isA<CatalogException>()),
      );
      expect(await catalog.covers('测试', ''), isEmpty);
      expect(hosts, ['lrclib.net', 'musicbrainz.org']);
      catalog.dispose();
    },
  );
  test(
    'empty strict lyrics broaden keywords and identical pending searches coalesce',
    () async {
      final gate = Completer<http.Response>();
      final queries = <Map<String, String>>[];
      final catalog = OnlineCatalog(
        requestGap: Duration.zero,
        client: MockClient((request) async {
          queries.add(request.url.queryParameters);
          if (queries.length == 1) return gate.future;
          return http.Response(
            jsonEncode([
              {'id': 2, 'plainLyrics': 'original', 'duration': 'bad'},
            ]),
            200,
          );
        }),
      );
      final one = catalog.lyrics('测试', '歌手');
      final two = catalog.lyrics('测试', '歌手');
      gate.complete(http.Response('[]', 200));
      expect((await one).single.lyrics, 'original');
      expect((await two).single.duration, isNull);
      expect(queries, [
        {'track_name': '测试', 'artist_name': '歌手'},
        {'q': '测试 歌手'},
      ]);
      catalog.dispose();
    },
  );
  test('missing 500px artwork falls back to a smaller thumbnail', () async {
    final paths = <String>[];
    final catalog = OnlineCatalog(
      requestGap: Duration.zero,
      client: MockClient((request) async {
        paths.add(request.url.path);
        return http.Response(
          request.url.path.endsWith('500') ? '' : 'image',
          request.url.path.endsWith('500') ? 404 : 200,
        );
      }),
    );
    final bytes = await catalog.coverBytes(
      const CatalogResult(
        id: '12345678-1234-1234-1234-123456789012',
        title: '',
        artist: '',
        album: '',
      ),
    );
    expect(utf8.decode(bytes), 'image');
    expect(paths.length, 2);
    catalog.dispose();
  });
  test(
    'malformed JSON reports a response problem and can be searched again',
    () async {
      var calls = 0;
      final catalog = OnlineCatalog(
        requestGap: Duration.zero,
        client: MockClient((_) async {
          calls++;
          return http.Response(
            calls == 1 ? '<html>error' : '{"recordings":[]}',
            200,
          );
        }),
      );
      await expectLater(
        catalog.covers('测试', ''),
        throwsA(
          isA<CatalogException>().having((e) => e.code, 'code', 'bad_response'),
        ),
      );
      expect(await catalog.covers('测试', ''), isEmpty);
      expect(calls, 2);
      catalog.dispose();
    },
  );
  test('short service backoff is honored before the one retry', () async {
    var now = DateTime(2026);
    final waits = <Duration>[];
    var calls = 0;
    final catalog = OnlineCatalog(
      now: () => now,
      delay: (wait) async {
        waits.add(wait);
        now = now.add(wait);
      },
      client: MockClient((_) async {
        calls++;
        return calls == 1 ? http.Response('', 503) : http.Response('[]', 200);
      }),
    );
    expect(await catalog.lyrics('测试', ''), isEmpty);
    expect(waits.first, const Duration(seconds: 2));
    expect(calls, 3); // retry exact once, then broaden the empty search.
    catalog.dispose();
  });
}
