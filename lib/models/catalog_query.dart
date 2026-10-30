import 'drive_entry.dart';
import 'song_details.dart';

class CatalogQuery {
  const CatalogQuery(this.title, this.artist);
  final String title, artist;

  factory CatalogQuery.fromSong(
    DriveEntry entry,
    SongDetails details,
    String? root,
  ) {
    var title = details.title?.trim() ?? entry.title;
    var artist = details.artist?.trim() ?? '';
    title = title.replaceFirst(RegExp(r'^\s*\d{1,3}[.、 _-]+'), '');
    title = title
        .replaceAll(
          RegExp(
            r'[\[【(（](?:flac|mp3|ape|wav|hi-?res|无损|高音质|320k(?:bps)?)[\]】)）]',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
    if (details.title?.isNotEmpty != true && title.contains(' - ')) {
      final split = title.indexOf(' - ');
      if (artist.isEmpty) artist = title.substring(0, split).trim();
      title = title.substring(split + 3).trim();
    }
    if (artist.isEmpty && !entry.demo) {
      final relative = root != null && entry.path.startsWith('$root/')
          ? entry.path.substring(root.length + 1).split('/')
          : <String>[];
      final candidate = relative.length >= 2 ? relative.first : entry.artist;
      if (!RegExp(
        r'^(音乐|music|audio|流行|摇滚|轻音乐|分类|其他|未知|下载|专辑.*|album.*)$',
        caseSensitive: false,
      ).hasMatch(candidate)) {
        artist = candidate;
      }
    }
    return CatalogQuery(title, artist);
  }
}
