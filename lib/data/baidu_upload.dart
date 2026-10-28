part of 'baidu_client.dart';

class UploadInput {
  const UploadInput({
    required this.name,
    required this.size,
    required this.read,
  });
  final String name;
  final int size;
  final Stream<List<int>> Function(int start, int end) read;
}

class _UploadRequest extends http.MultipartRequest with http.Abortable {
  _UploadRequest(super.method, super.url, this.abortTrigger);
  @override
  final Future<void>? abortTrigger;
}

extension BaiduUpload on BaiduClient {
  static const blockSize = 4 * 1024 * 1024;
  static const maxUploadSize = 2 * 1024 * 1024 * 1024;

  static String childPath(String directory, String name) {
    if (!directory.startsWith('/') ||
        directory.split('/').any((p) => p == '..' || p == '.') ||
        name.trim().isEmpty ||
        name == '.' ||
        name == '..' ||
        RegExp(r'[/\\\x00-\x1f:*?"<>|]').hasMatch(name)) {
      throw const DriveException('文件或目录名称不合法，请勿包含斜杠、问号等特殊字符', code: 'bad_path');
    }
    final parent = directory.replaceAll(RegExp(r'/+$'), '');
    return '$parent/$name';
  }

  Future<void> createFolder(String directory, String name) async {
    await _api(
      'file',
      {'method': 'create'},
      form: {
        'path': childPath(directory, name.trim()),
        'size': '0',
        'isdir': '1',
        'rtype': '0',
      },
    );
  }

  Future<DriveEntry> uploadFile(
    UploadInput input,
    String directory, {
    required TransferControl control,
    required void Function(int bytes, String phase) onProgress,
  }) async {
    final path = childPath(directory, input.name);
    final generation = _generation;
    void check() {
      control.check();
      if (_generation != generation) {
        throw const DriveException('网盘连接已更改，上传已停止', code: 'cancelled');
      }
    }

    if (input.size <= 0 || input.size > maxUploadSize) {
      throw const DriveException('请选择大于 0 且不超过 2 GB 的音乐文件', code: 'bad_size');
    }
    check();
    final hashes = <String>[];
    for (var offset = 0; offset < input.size; offset += blockSize) {
      final end = (offset + blockSize).clamp(0, input.size);
      var length = 0;
      final digest = await md5
          .bind(
            input.read(offset, end).map((chunk) {
              check();
              length += chunk.length;
              return chunk;
            }),
          )
          .first;
      if (length != end - offset) {
        throw const DriveException('无法完整读取手机文件，请重新选择', code: 'local_read');
      }
      hashes.add(digest.toString());
      onProgress(end, '校验文件');
    }
    check();
    onProgress(0, '准备上传');
    final common = {
      'path': path,
      'size': '${input.size}',
      'isdir': '0',
      'block_list': jsonEncode(hashes),
      'rtype': '0',
    };
    final pre = await _api(
      'file',
      {'method': 'precreate'},
      form: {...common, 'autoinit': '1'},
      control: control,
    );
    check();
    final uploadId = pre['uploadid'] as String? ?? '';
    // Some rapid-upload responses have already created the final file.
    if (pre['return_type'] == 2 && pre['fs_id'] != null) {
      return DriveEntry.fromJson({
        ...pre,
        'path': pre['path'] ?? path,
        'name': input.name,
        'size': input.size,
      });
    }
    if (uploadId.isEmpty) {
      throw const DriveException(
        '百度未返回上传 ID，请刷新目录检查是否已秒传后重试',
        code: 'invalid_response',
      );
    }
    final requiredParts = pre['block_list'];
    final parts = requiredParts is List && requiredParts.isNotEmpty
        ? requiredParts
        : pre['return_type'] == 2
        ? <dynamic>[]
        : List.generate(hashes.length, (i) => i);
    final seen = <int>{};
    for (final part in parts) {
      if (part is! int ||
          part < 0 ||
          part >= hashes.length ||
          !seen.add(part)) {
        throw const DriveException('百度返回了无效的分片列表', code: 'invalid_response');
      }
    }
    var sent = input.size;
    for (final part in seen) {
      sent -= ((part + 1) * blockSize).clamp(0, input.size) - part * blockSize;
    }
    onProgress(sent, '上传中');
    for (final part in seen) {
      final offset = part * blockSize;
      final end = (offset + blockSize).clamp(0, input.size);
      var token = await accessToken();
      for (var attempt = 0; ; attempt++) {
        check();
        final uri = Uri.https('d.pcs.baidu.com', '/rest/2.0/pcs/superfile2', {
          'method': 'upload',
          'access_token': token,
          'type': 'tmpfile',
          'path': path,
          'uploadid': uploadId,
          'partseq': '$part',
        });
        var count = 0;
        final request = _UploadRequest('POST', uri, control.aborted)
          ..files.add(
            http.MultipartFile(
              'file',
              input.read(offset, end).map((bytes) {
                check();
                count += bytes.length;
                onProgress(sent + count, '上传中');
                return bytes;
              }),
              end - offset,
              filename: input.name,
            ),
          );
        Map<String, dynamic> result;
        try {
          result = await _json(uri, request: request, control: control);
        } on DriveException catch (e) {
          if (attempt == 0 && ['-6', '110', '111'].contains(e.code)) {
            token = await accessToken(rejectedToken: token);
            continue;
          }
          rethrow;
        }
        if ('${result['md5']}'.toLowerCase() != hashes[part]) {
          throw const DriveException(
            '上传分片校验失败，文件未提交，请重新选择后重试',
            code: 'checksum',
          );
        }
        break;
      }
      sent += end - offset;
    }
    check();
    onProgress(input.size, '保存到网盘');
    final created = await _api(
      'file',
      {'method': 'create'},
      form: {...common, 'uploadid': uploadId},
      control: control,
    );
    // Do not undo a completed remote create on a late cancellation.
    if (created['fs_id'] == null || created['path'] is! String) {
      throw const DriveException(
        '百度返回结果不完整，请刷新目录确认上传结果',
        code: 'invalid_response',
      );
    }
    return DriveEntry.fromJson({
      ...created,
      'name': input.name,
      'size': input.size,
    });
  }
}
