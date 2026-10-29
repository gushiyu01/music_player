class LyricLine {
  const LyricLine(this.milliseconds, this.text);
  final int milliseconds;
  final String text;
}

class Lyrics {
  Lyrics(this.text) {
    final offset =
        int.tryParse(
          RegExp(
                r'\[offset:([+-]?\d+)\]',
                caseSensitive: false,
              ).firstMatch(text)?.group(1) ??
              '',
        ) ??
        0;
    final stamps = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');
    for (final raw in text.split('\n')) {
      final matches = stamps.allMatches(raw).toList();
      if (matches.isEmpty) continue;
      final words = raw.substring(matches.last.end).trim();
      for (final match in matches) {
        final seconds = int.parse(match[2]!);
        if (seconds >= 60) continue;
        final fraction = (match[3] ?? '').padRight(3, '0');
        final time =
            int.parse(match[1]!) * 60000 +
            seconds * 1000 +
            int.parse(fraction) +
            offset;
        lines.add(LyricLine(time < 0 ? 0 : time, words));
      }
    }
    lines.sort((a, b) => a.milliseconds.compareTo(b.milliseconds));
  }
  final String text;
  final List<LyricLine> lines = [];
  int activeAt(Duration position) {
    var low = 0;
    var high = lines.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (lines[middle].milliseconds <= position.inMilliseconds) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low - 1;
  }
}

class SongDetails {
  const SongDetails({
    this.title,
    this.artist,
    this.album,
    this.lyrics,
    this.coverPath,
    this.lyricsSource,
    this.coverSource,
  });
  final String? title,
      artist,
      album,
      lyrics,
      coverPath,
      lyricsSource,
      coverSource;
  SongDetails copyWith({
    String? title,
    String? artist,
    String? album,
    String? lyrics,
    String? coverPath,
    String? lyricsSource,
    String? coverSource,
  }) => SongDetails(
    title: title ?? this.title,
    artist: artist ?? this.artist,
    album: album ?? this.album,
    lyrics: lyrics ?? this.lyrics,
    coverPath: coverPath ?? this.coverPath,
    lyricsSource: lyricsSource ?? this.lyricsSource,
    coverSource: coverSource ?? this.coverSource,
  );
  Map<String, dynamic> toJson() => {
    'title': title,
    'artist': artist,
    'album': album,
    'lyrics': lyrics,
    'coverPath': coverPath,
    'lyricsSource': lyricsSource,
    'coverSource': coverSource,
  };
  factory SongDetails.fromJson(Map<String, dynamic> value) => SongDetails(
    title: value['title'] as String?,
    artist: value['artist'] as String?,
    album: value['album'] as String?,
    lyrics: value['lyrics'] as String?,
    coverPath: value['coverPath'] as String?,
    lyricsSource: value['lyricsSource'] as String?,
    coverSource: value['coverSource'] as String?,
  );
}
