import 'dart:convert';

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
}
