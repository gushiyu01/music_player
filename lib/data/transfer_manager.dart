import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/drive_entry.dart';
import 'baidu_client.dart';
import 'offline_library.dart';
import 'transfer_control.dart';

enum TransferStatus { queued, running, done, failed, cancelled }

class MusicTransfer {
  MusicTransfer.download(DriveEntry value)
    : entry = value,
      input = null,
      destination = value.parent;
  MusicTransfer.upload(this.input, this.destination) : entry = null;
  final DriveEntry? entry;
  final UploadInput? input;
  final String destination;
  bool get uploading => input != null;
  String get name => input?.name ?? entry!.name;
  int get total => input?.size ?? entry!.size;
  int bytes = 0;
  String phase = '等待中';
  String? error;
  DriveEntry? result;
  TransferStatus status = TransferStatus.queued;
  TransferControl control = TransferControl();
  bool get active =>
      status == TransferStatus.queued || status == TransferStatus.running;
  double? get progress => total > 0 ? (bytes / total).clamp(0, 1) : null;
}

class TransferManager extends ChangeNotifier {
  TransferManager(this.client, this.library, {AssetBundle? assets})
    : assets = assets ?? rootBundle;
  final BaiduClient client;
  final OfflineLibrary library;
  final AssetBundle assets;
  final List<MusicTransfer> tasks = [];
  bool Function(String directory)? canUploadTo;
  bool _draining = false;
  DateTime _lastProgress = DateTime(2000);
  int get activeCount => tasks.where((t) => t.active).length;

  MusicTransfer? downloadTask(DriveEntry entry) {
    for (final task in tasks.reversed) {
      if (!task.uploading && library.key(task.entry!) == library.key(entry)) {
        return task;
      }
    }
    return null;
  }

  void download(DriveEntry entry) {
    if (!entry.isAudio || library.localPath(entry) != null) return;
    final previous = downloadTask(entry);
    if (previous?.active == true) return;
    if (previous != null && previous.status != TransferStatus.done) {
      retry(previous);
      return;
    }
    tasks.add(MusicTransfer.download(entry));
    notifyListeners();
    unawaited(_drain());
  }

  void upload(UploadInput input, String directory) {
    if (canUploadTo?.call(directory) == false) {
      throw const DriveException('只能上传到指定音乐目录内', code: 'outside_root');
    }
    tasks.add(MusicTransfer.upload(input, directory));
    notifyListeners();
    unawaited(_drain());
  }

  void cancel(MusicTransfer task) {
    if (!task.active || task.control.cancelled) return;
    task.control.cancel();
    if (task.status == TransferStatus.queued) {
      task.status = TransferStatus.cancelled;
    }
    task.phase = task.status == TransferStatus.cancelled ? '已取消' : '正在取消';
    notifyListeners();
  }

  void cancelAll() {
    for (final task in tasks) {
      cancel(task);
    }
  }

  void retry(MusicTransfer task) {
    if (task.active || task.status == TransferStatus.done) return;
    if (task.uploading && canUploadTo?.call(task.destination) == false) {
      task.status = TransferStatus.failed;
      task.error = '原上传目录不在当前音乐目录内，请在音乐库重新选择文件上传';
      notifyListeners();
      return;
    }
    task.control = TransferControl();
    task.bytes = 0;
    task.error = null;
    task.phase = '等待中';
    task.status = TransferStatus.queued;
    notifyListeners();
    unawaited(_drain());
  }

  void _progress(MusicTransfer task, int bytes, String phase) {
    task.bytes = bytes;
    task.phase = phase;
    if (DateTime.now().difference(_lastProgress).inMilliseconds >= 150) {
      _lastProgress = DateTime.now();
      notifyListeners();
    }
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (true) {
        final pending = tasks.where((t) => t.status == TransferStatus.queued);
        if (pending.isEmpty) break;
        final task = pending.first;
        task.status = TransferStatus.running;
        notifyListeners();
        try {
          if (task.uploading) {
            task.result = await client.uploadFile(
              task.input!,
              task.destination,
              control: task.control,
              onProgress: (b, p) => _progress(task, b, p),
            );
          } else {
            await _download(task);
          }
          task.status = TransferStatus.done;
          task.phase = '已完成';
        } catch (failure) {
          task.status =
              task.control.cancelled ||
                  (failure is DriveException && failure.code == 'cancelled')
              ? TransferStatus.cancelled
              : TransferStatus.failed;
          task.error = task.status == TransferStatus.cancelled
              ? '传输已取消'
              : failure is DriveException
              ? failure.message
              : failure is FileSystemException
              ? '本地读写失败，请检查剩余空间或重新选择文件'
              : '传输中断，请检查网络后重试';
          task.phase = task.status == TransferStatus.cancelled ? '已取消' : '传输失败';
          task.control.cancel();
        }
        notifyListeners();
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> _download(MusicTransfer task) async {
    final entry = task.entry!;
    final control = task.control;
    control.check();
    final partial = library.partialFor(entry);
    IOSink? sink;
    try {
      Stream<List<int>> stream;
      int? expected;
      if (entry.demo) {
        final data = await assets.load(entry.path);
        stream = Stream.value(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
        expected = data.lengthInBytes;
      } else {
        final response = await client.openStream(entry, control: control);
        final contentRange = response.headers['content-range'];
        if (response.statusCode == 206 &&
            (contentRange == null ||
                !RegExp(r'^bytes 0-\d+/\d+$').hasMatch(contentRange))) {
          await response.stream.listen((_) {}).cancel();
          throw const DriveException('百度返回了不完整的文件范围，请重试', code: 'bad_range');
        }
        final type = response.headers['content-type'] ?? '';
        if (type.contains('json') || type.contains('text/html')) {
          await response.stream.listen((_) {}).cancel();
          throw const DriveException(
            '百度没有返回音乐文件，请检查下载权限',
            code: 'invalid_response',
          );
        }
        expected = contentRange == null
            ? response.contentLength
            : int.parse(contentRange.split('/').last);
        stream = response.stream.timeout(const Duration(seconds: 30));
      }
      control.check();
      sink = partial.openWrite();
      var bytes = 0;
      await for (final chunk in stream) {
        control.check();
        bytes += chunk.length;
        if (expected != null && bytes > expected) {
          throw const DriveException('下载长度异常，请重试', code: 'incomplete');
        }
        // addStream observes disk backpressure and propagates write failures.
        await sink.addStream(Stream.value(chunk));
        _progress(task, bytes, '下载中');
      }
      await sink.flush();
      await sink.close();
      sink = null;
      control.check();
      if (bytes == 0 ||
          (expected != null && bytes != expected) ||
          (entry.size > 0 && entry.size != bytes)) {
        throw const DriveException(
          '文件未完整下载或已在网盘中更改，请刷新后重试',
          code: 'incomplete',
        );
      }
      await library.commit(entry, bytes);
      task.bytes = bytes;
    } finally {
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {
          /* Original failure is retained. */
        }
      }
      if (await partial.exists()) await partial.delete();
    }
  }
}
