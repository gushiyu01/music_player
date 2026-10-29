import 'dart:convert';
import 'dart:typed_data';

import 'package:charset/charset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/data/audio_tags.dart';
import 'package:music_player/models/song_details.dart';

List<int> number(int value, {bool little = false, bool sync = false}) {
  final width = sync ? 7 : 8;
  final data = [
    for (var i = 3; i >= 0; i--) (value >> (i * width)) & (sync ? 127 : 255),
  ];
  return little ? data.reversed.toList() : data;
}

Uint8List id3({int version = 3, bool truncated = false}) {
  final frames = <int>[];
  void frame(String id, List<int> data) => frames.addAll([
    ...ascii.encode(id),
    ...number(data.length, sync: version == 4),
    0,
    0,
    ...data,
  ]);
  frame('TIT2', [3, ...utf8.encode('晴天')]);
  frame('TPE1', [3, ...utf8.encode('周杰伦')]);
  frame('USLT', [
    3,
    ...ascii.encode('zho'),
    0,
    ...utf8.encode('[00:01.00]测试歌词'),
  ]);
  frame('APIC', [0, ...ascii.encode('image/png'), 0, 3, 0, 137, 80, 78, 71]);
  final value = [
    73,
    68,
    51,
    version,
    0,
    0,
    ...number(frames.length, sync: true),
    ...frames,
  ];
  return Uint8List.fromList(truncated ? value.sublist(0, 12) : value);
}

void main() {
  test(
    'LRC multiple timestamps, offsets and fractional precision are ordered',
    () {
      final lyrics = Lyrics(
        '[ar:测试]\n[offset:-100]\n[00:02.5][00:03.050]第二行\n[00:00.01]第一行\n[00:99]无效',
      );
      expect(lyrics.lines.map((l) => l.milliseconds), [0, 2400, 2950]);
      expect(lyrics.activeAt(const Duration(milliseconds: 2450)), 1);
      expect(Lyrics('[00:05]开场').activeAt(Duration.zero), -1);
      expect(Lyrics('纯文本歌词').lines, isEmpty);
    },
  );
  for (final version in [3, 4]) {
    test(
      'ID3v2.$version extracts embedded metadata, lyrics and front picture',
      () {
        final tags = AudioTags.parse(id3(version: version));
        expect(tags.title, '晴天');
        expect(tags.artist, '周杰伦');
        expect(tags.lyrics, '[00:01.00]测试歌词');
        expect(tags.cover, [137, 80, 78, 71]);
      },
    );
  }
  test('truncated and malformed headers are safe', () {
    expect(AudioTags.parse(id3(truncated: true)).cover, isNull);
    expect(
      AudioTags.parse(
        Uint8List.fromList([102, 76, 97, 67, 132, 255, 255, 255]),
      ).title,
      isNull,
    );
  });
  test(
    'UTF8 BOM, UTF16 and Chinese GBK lyrics decode without replacement characters',
    () {
      expect(
        AudioTags.decodeText([239, 187, 191, ...utf8.encode('中文歌词')]),
        '中文歌词',
      );
      expect(AudioTags.decodeText([255, 254, 45, 78, 135, 101]), '中文');
      expect(AudioTags.decodeText(gbk.encode('中文歌词')), '中文歌词');
    },
  );
  test('FLAC comments and front picture are read without audio decoding', () {
    final comments = [
      for (final text in ['TITLE=晴天', 'ARTIST=周杰伦', 'LYRICS=[00:01]测试']) ...[
        ...number(utf8.encode(text).length, little: true),
        ...utf8.encode(text),
      ],
    ];
    final block = [
      ...number(0, little: true),
      ...number(3, little: true),
      ...comments,
    ];
    final picture = [
      ...number(3),
      ...number(9),
      ...ascii.encode('image/png'),
      ...number(0),
      ...number(1),
      ...number(1),
      ...number(24),
      ...number(0),
      ...number(4),
      137,
      80,
      78,
      71,
    ];
    final bytes = Uint8List.fromList([
      102,
      76,
      97,
      67,
      4,
      ...number(block.length).sublist(1),
      ...block,
      134,
      ...number(picture.length).sublist(1),
      ...picture,
    ]);
    final tags = AudioTags.parse(bytes);
    expect(tags.title, '晴天');
    expect(tags.artist, '周杰伦');
    expect(tags.lyrics, '[00:01]测试');
    expect(tags.cover, [137, 80, 78, 71]);
  });
}
