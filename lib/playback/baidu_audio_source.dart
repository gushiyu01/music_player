// This package API is experimental. The resolved just_audio version is locked
// and its Range/redirect behavior is covered by our client tests.
// ignore_for_file: experimental_member_use

import 'package:just_audio/just_audio.dart';

import '../data/baidu_client.dart';
import '../models/drive_entry.dart';

/// The decoder's loopback requests stay on the phone. Audio bytes are fetched
/// directly from Baidu; no remote application server participates.
class BaiduAudioSource extends StreamAudioSource {
  BaiduAudioSource(this.client, this.entry);
  final BaiduClient client;
  final DriveEntry entry;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final response = await client.openStream(entry, start: start, end: end);
    final range = RegExp(
      r'^bytes (\d+)-(\d+)/(\d+|\*)$',
    ).firstMatch(response.headers['content-range'] ?? '');
    if (response.statusCode == 206 && range == null) {
      await response.stream.listen((_) {}).cancel();
      throw const DriveException('百度分段响应格式异常，请重试播放', code: 'invalid_range');
    }
    final type = (response.headers['content-type'] ?? 'audio/mpeg')
        .split(';')
        .first;
    if (type.contains('json') || type.contains('html')) {
      await response.stream.listen((_) {}).cancel();
      throw const DriveException('百度未返回音频数据，请检查授权和下载权限', code: 'not_audio');
    }
    final offset = range == null ? 0 : int.parse(range.group(1)!);
    if (start != null && offset != start) {
      await response.stream.listen((_) {}).cancel();
      throw const DriveException('百度返回了错误的音频分段，请重试', code: 'invalid_range');
    }
    final length = response.contentLength;
    final total = range == null ? length : int.tryParse(range.group(3)!);
    return StreamAudioResponse(
      sourceLength: total,
      contentLength:
          length ??
          (range == null ? null : int.parse(range.group(2)!) - offset + 1),
      offset: offset,
      stream: response.stream.handleError((Object _) {
        throw const DriveException('音频连接中断，请检查网络后重试', code: 'network');
      }),
      contentType: type,
      rangeRequestsSupported:
          response.statusCode == 206 ||
          response.headers['accept-ranges'] == 'bytes',
    );
  }
}
