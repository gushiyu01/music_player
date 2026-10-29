part of 'baidu_client.dart';

extension BaiduFileActions on BaiduClient {
  Future<void> moveSong(DriveEntry entry, String destination) async {
    _validateSong(entry);
    BaiduUpload.childPath(destination, entry.name);
    if (destination == entry.parent) {
      throw const DriveException('歌曲已经在这个目录中', code: 'same_directory');
    }
    await _manageSong('move', entry, [
      {
        'path': entry.path,
        'dest': destination,
        'newname': entry.name,
        'ondup': 'fail',
      },
    ]);
  }

  Future<void> deleteSong(DriveEntry entry) async {
    _validateSong(entry);
    await _manageSong('delete', entry, [entry.path]);
  }

  void _validateSong(DriveEntry entry) {
    if (entry.demo ||
        !entry.isAudio ||
        !entry.path.startsWith('/') ||
        entry.path != BaiduUpload.childPath(entry.parent, entry.name)) {
      throw const DriveException('只能操作网盘中的单首音乐文件', code: 'bad_path');
    }
  }

  Future<void> _manageSong(
    String operation,
    DriveEntry entry,
    List<Object> files,
  ) async {
    final data = await _api(
      'file',
      {'method': 'filemanager', 'opera': operation},
      form: {
        'async': '0',
        'filelist': jsonEncode(files),
        if (operation == 'move') 'ondup': 'fail',
      },
    );
    final info = data['info'];
    if (data['taskid'] != null && '${data['taskid']}' != '0' ||
        info is! List ||
        info.length != 1 ||
        info.single is! Map) {
      throw const DriveException(
        '百度未返回明确的操作结果，请刷新目录核实后再操作',
        code: 'uncertain_result',
      );
    }
    final result = info.single as Map;
    final code = '${result['errno']}';
    if (code != '0') {
      throw DriveException(BaiduClient._apiMessage(code), code: code);
    }
  }
}
