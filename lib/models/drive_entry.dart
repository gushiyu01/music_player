class DriveEntry {
  const DriveEntry({
    required this.id,
    required this.name,
    required this.path,
    this.isDirectory = false,
    this.size = 0,
    this.demo = false,
  });

  factory DriveEntry.fromJson(Map<String, dynamic> json) => DriveEntry(
    id: '${json['fs_id'] ?? json['id']}',
    name: json['server_filename'] as String? ?? json['name'] as String? ?? '',
    path: json['path'] as String? ?? '/',
    isDirectory: json['isdir'] == 1,
    size: (json['size'] as num?)?.toInt() ?? 0,
    demo: json['demo'] == true,
  );

  final String id;
  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final bool demo;

  String get parent {
    final slash = path.lastIndexOf('/');
    return slash <= 0 ? '/' : path.substring(0, slash);
  }

  String get artist => demo ? '云间 · 原创合成试听' : parent.split('/').last;

  String get extension =>
      name.contains('.') ? name.split('.').last.toLowerCase() : '';
  bool get isAudio =>
      !isDirectory &&
      const {
        'mp3',
        'flac',
        'm4a',
        'aac',
        'wav',
        'ogg',
        'opus',
        'aiff',
        'aif',
        'amr',
      }.contains(extension);
  String get title =>
      isAudio ? name.substring(0, name.length - extension.length - 1) : name;
  Map<String, dynamic> toJson() => {
    'fs_id': id,
    'name': name,
    'path': path,
    'isdir': isDirectory ? 1 : 0,
    'size': size,
    'demo': demo,
  };
}

class DirectoryPage {
  const DirectoryPage(this.entries, this.nextStart);
  final List<DriveEntry> entries;
  final int? nextStart;
}

const demoTracks = [
  DriveEntry(
    id: 'demo-dawn',
    name: '晨光 · Dawn.wav',
    path: 'assets/audio/dawn.wav',
    demo: true,
  ),
  DriveEntry(
    id: 'demo-tide',
    name: '潮汐 · Tide.wav',
    path: 'assets/audio/tide.wav',
    demo: true,
  ),
];
