import '../data/baidu_client.dart';

/// A user-selected music folder. No file-list request may use the drive root.
class MusicDirectory {
  static String normalize(String input) {
    final path = input.trim();
    if (!path.startsWith('/') ||
        RegExp(r'[\\\x00-\x1f:*?"<>|]').hasMatch(path) ||
        path.split('/').any((part) => part == '.' || part == '..')) {
      throw const DriveException(
        '请填写 /音乐 这样的网盘绝对路径，不要包含 .. 或特殊字符',
        code: 'bad_path',
      );
    }
    final parts = path.split('/').where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty || parts.any((part) => part.trim().isEmpty)) {
      throw const DriveException('请选择具体的音乐目录，不能使用网盘根目录 /', code: 'bad_path');
    }
    return '/${parts.join('/')}';
  }

  static bool contains(String? root, String path) {
    if (root == null) return false;
    try {
      final normalized = normalize(path);
      return normalized == root || normalized.startsWith('$root/');
    } on DriveException {
      return false;
    }
  }
}
