// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../data/baidu_client.dart';
import '../data/playback_cache.dart';
import '../models/drive_entry.dart';
import 'baidu_audio_source.dart';

/// One full stream fills a disk file; decoder reads tail that file rather than
/// buffering the whole song in memory. Seeks beyond the tail use Baidu Range.
class CachingAudioSource extends StreamAudioSource {
  CachingAudioSource(this.client, this.entry, this.cache, {AssetBundle? assets})
    : assets = assets ?? rootBundle;
  final BaiduClient client;
  final DriveEntry entry;
  final PlaybackCache cache;
  final AssetBundle assets;
  final _ready = Completer<void>();
  Completer<void> _changed = Completer<void>();
  Future<void>? _work;
  CacheWrite? _write;
  int _bytes = 0;
  int? _total;
  String _type = 'audio/mpeg';
  bool _finished = false, _closed = false;
  Object? _failure;

  void _signal() {
    final previous = _changed;
    _changed = Completer<void>();
    if (!previous.isCompleted) previous.complete();
  }

  Future<void> _fill() async {
    IOSink? sink;
    try {
      final write = await cache.begin(entry);
      _write = write;
      if (write == null) return;
      if (_closed) {
        write.control.cancel();
        return;
      }
      Stream<List<int>> stream;
      if (entry.demo) {
        final data = await assets.load(entry.path);
        _total = data.lengthInBytes;
        _type = 'audio/wav';
        stream = Stream.value(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
      } else {
        final response = await client.openStream(entry, control: write.control);
        final range = RegExp(
          r'^bytes 0-(\d+)/(\d+)$',
        ).firstMatch(response.headers['content-range'] ?? '');
        _type = (response.headers['content-type'] ?? 'audio/mpeg')
            .split(';')
            .first;
        if ((response.statusCode == 206 && range == null) ||
            _type.contains('json') ||
            _type.contains('html')) {
          await response.stream.listen((_) {}).cancel();
          throw const DriveException('百度未返回完整音频数据', code: 'invalid_response');
        }
        _total = range == null
            ? response.contentLength
            : int.parse(range.group(2)!);
        stream = response.stream.timeout(const Duration(seconds: 30));
      }
      write.control.check();
      sink = write.file.openWrite();
      // Ensure the tailing reader sees a real file, even before the first chunk.
      await sink.flush();
      if (!_ready.isCompleted) _ready.complete();
      await for (final chunk in _cancellable(stream, write)) {
        write.control.check();
        if (_bytes + chunk.length > cache.maximumBytes ||
            (_total != null && _bytes + chunk.length > _total!)) {
          throw const DriveException('音频长度异常', code: 'incomplete');
        }
        await sink.addStream(Stream.value(chunk));
        await sink.flush();
        _bytes += chunk.length;
        _signal();
      }
      await sink.close();
      sink = null;
      write.control.check();
      if (_total != null && _bytes != _total) {
        throw const DriveException('音频未完整接收，请重试', code: 'incomplete');
      }
      if (!await cache.complete(write, _bytes)) {
        throw const FileSystemException('Unable to save playback cache');
      }
    } catch (failure) {
      _failure = failure;
    } finally {
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {
          /* Retain the first failure. */
        }
      }
      final write = _write;
      if (write != null && !write.done.isCompleted) {
        try {
          await cache.discard(write);
        } catch (_) {
          /* Cache is optional. */
        }
      }
      _finished = true;
      if (!_ready.isCompleted) _ready.complete();
      _signal();
    }
  }

  Stream<List<int>> _cancellable(Stream<List<int>> stream, CacheWrite write) {
    late StreamController<List<int>> output;
    StreamSubscription<List<int>>? subscription;
    output = StreamController<List<int>>(
      onListen: () {
        subscription = stream.listen(
          output.add,
          onError: output.addError,
          onDone: output.close,
        );
        unawaited(
          write.control.aborted.then((_) async {
            await subscription?.cancel();
            if (!output.isClosed) await output.close();
          }),
        );
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () => subscription?.cancel(),
    );
    return output.stream;
  }

  Future<void> close() async {
    _closed = true;
    if (_total == null || _bytes != _total) _write?.control.cancel();
    _signal();
    await _work;
  }

  Stream<List<int>> _read(int start, int? end) async* {
    var offset = start;
    while (!_closed && (end == null || offset < end)) {
      final changed = _changed.future;
      final available = end == null ? _bytes : min(_bytes, end);
      if (_failure != null) {
        final response = await _direct(offset, end);
        yield* response.stream;
        return;
      } else if (offset < available) {
        final stop = min(available, offset + 64 * 1024);
        yield* _write!.file.openRead(offset, stop);
        offset = stop;
      } else if (_finished) {
        return;
      } else {
        await changed;
      }
    }
  }

  Future<StreamAudioResponse> _direct(int? start, int? end) async {
    if (!entry.demo) return BaiduAudioSource(client, entry).request(start, end);
    final data = await assets.load(entry.path);
    final first = start ?? 0;
    final last = min(end ?? data.lengthInBytes, data.lengthInBytes);
    return StreamAudioResponse(
      sourceLength: data.lengthInBytes,
      contentLength: last - first,
      offset: first,
      contentType: 'audio/wav',
      stream: Stream.value(
        data.buffer.asUint8List(data.offsetInBytes + first, last - first),
      ),
    );
  }

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    _work ??= _fill();
    await _ready.future;
    final offset = start ?? 0;
    if (_write == null ||
        (_failure != null && _bytes == 0) ||
        offset > _bytes) {
      return _direct(start, end);
    }
    return StreamAudioResponse(
      sourceLength: _total,
      contentLength: (end ?? _total) == null ? null : (end ?? _total!) - offset,
      offset: offset,
      contentType: _type,
      rangeRequestsSupported: true,
      stream: _read(offset, end ?? _total),
    );
  }
}
