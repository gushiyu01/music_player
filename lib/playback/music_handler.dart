import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../data/baidu_client.dart';
import '../data/offline_library.dart';
import '../models/drive_entry.dart';
import 'baidu_audio_source.dart';

class MusicHandler extends BaseAudioHandler with SeekHandler {
  MusicHandler(this.client, {this.library}) {
    player.playbackEventStream.listen((_) => _broadcast());
    player.errorStream.listen((_) {
      if (!loading.value) {
        error.value = '播放中断，请检查网络后点击重试';
        _broadcast();
      }
    });
    player.durationStream.listen((duration) {
      if (mediaItem.value == null || duration == null) return;
      final updated = mediaItem.value!.copyWith(duration: duration);
      mediaItem.add(updated);
      final items = [...queue.value];
      if (index < items.length) {
        items[index] = updated;
        queue.add(items);
      }
    });
    player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed && !loading.value) {
        unawaited(_onCompleted());
      }
    });
  }

  final BaiduClient client;
  final OfflineLibrary? library;
  bool onlineOnly = false;
  final AudioPlayer player = AudioPlayer();
  final ValueNotifier<String?> error = ValueNotifier(null);
  final ValueNotifier<bool> loading = ValueNotifier(false);
  final ValueNotifier<bool> shuffled = ValueNotifier(false);
  final ValueNotifier<AudioServiceRepeatMode> repeat = ValueNotifier(
    AudioServiceRepeatMode.none,
  );
  List<DriveEntry> entries = [];
  int index = 0;
  int _loadGeneration = 0;
  bool _loaded = false;
  Duration _resumePosition = Duration.zero;
  Duration get currentPosition => _loaded ? player.position : _resumePosition;

  Future<void> configureSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    session.becomingNoisyEventStream.listen((_) => unawaited(pause()));
  }

  void restore(List<DriveEntry> tracks, int current, Duration position) {
    if (tracks.isEmpty) return;
    entries = List.unmodifiable(tracks);
    index = current.clamp(0, tracks.length - 1);
    _resumePosition = position;
    queue.add(tracks.map(_item).toList());
    mediaItem.add(queue.value[index]);
    _broadcast();
  }

  MediaItem _item(DriveEntry entry) => MediaItem(
    id: entry.id,
    title: entry.title,
    artist: entry.demo ? '云间 · 原创合成试听' : entry.artist,
    album: entry.demo
        ? '离线演示'
        : entry.path
              .substring(0, entry.path.lastIndexOf('/'))
              .replaceAll('/', ' / '),
  );

  Future<void> playEntries(
    List<DriveEntry> tracks,
    int current, {
    bool onlineOnly = false,
  }) async {
    if (tracks.isEmpty) return;
    entries = List.unmodifiable(tracks);
    this.onlineOnly = onlineOnly;
    queue.add(tracks.map(_item).toList());
    await _load(current.clamp(0, tracks.length - 1));
  }

  Future<void> _load(int current, {Duration position = Duration.zero}) async {
    final generation = ++_loadGeneration;
    index = current;
    _resumePosition = position;
    _loaded = false;
    error.value = null;
    loading.value = true;
    mediaItem.add(queue.value[index]);
    _broadcast();
    try {
      await player.stop();
      if (generation != _loadGeneration) return;
      final entry = entries[current];
      final local = onlineOnly ? null : library?.localPath(entry);
      mediaItem.add(
        queue.value[index].copyWith(
          extras: {
            'source': local != null
                ? 'local'
                : entry.demo
                ? 'demo'
                : 'online',
          },
        ),
      );
      final source = local != null
          ? AudioSource.file(local)
          : entry.demo
          ? AudioSource.asset(entry.path)
          : BaiduAudioSource(client, entry);
      await player.setAudioSource(source, initialPosition: position);
      if (generation != _loadGeneration) return;
      _loaded = true;
      loading.value = false;
      unawaited(_startPlayer());
    } catch (failure) {
      if (generation == _loadGeneration) {
        loading.value = false;
        error.value = failure is DriveException
            ? failure.message
            : '无法播放这首音乐，请检查网络、文件格式或百度下载权限后重试';
        _broadcast();
      }
    }
  }

  Future<void> _startPlayer() async {
    try {
      await player.play();
    } catch (_) {
      error.value = '播放失败，请检查网络后重试';
      _broadcast();
    }
  }

  void _broadcast() {
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          player.playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: error.value != null
            ? AudioProcessingState.error
            : loading.value
            ? AudioProcessingState.loading
            : switch (player.processingState) {
                ProcessingState.idle => AudioProcessingState.idle,
                ProcessingState.loading => AudioProcessingState.loading,
                ProcessingState.buffering => AudioProcessingState.buffering,
                ProcessingState.ready => AudioProcessingState.ready,
                ProcessingState.completed => AudioProcessingState.completed,
              },
        playing: player.playing,
        updatePosition: _loaded ? player.position : _resumePosition,
        bufferedPosition: player.bufferedPosition,
        queueIndex: entries.isEmpty ? null : index,
        repeatMode: repeat.value,
        shuffleMode: shuffled.value
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
        errorCode: error.value == null ? null : 1,
        errorMessage: error.value,
      ),
    );
  }

  Future<void> _onCompleted() async {
    if (repeat.value == AudioServiceRepeatMode.one) {
      await _load(index);
    } else if (shuffled.value ||
        index + 1 < entries.length ||
        repeat.value == AudioServiceRepeatMode.all) {
      await skipToNext();
    } else {
      await player.pause();
      await player.seek(Duration.zero);
      _broadcast();
    }
  }

  @override
  Future<void> play() async {
    if (entries.isEmpty || loading.value) return;
    if (!_loaded || error.value != null) {
      await _load(index, position: _loaded ? player.position : _resumePosition);
    } else {
      unawaited(_startPlayer());
    }
  }

  @override
  Future<void> pause() async {
    await player.pause();
    _broadcast();
  }

  @override
  Future<void> seek(Duration position) async {
    _resumePosition = position;
    if (_loaded) await player.seek(position);
    _broadcast();
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index >= 0 && index < entries.length) await _load(index);
  }

  @override
  Future<void> skipToNext() async {
    if (entries.isEmpty) return;
    final next = shuffled.value && entries.length > 1
        ? (index + 1 + Random().nextInt(entries.length - 1)) % entries.length
        : (index + 1) % entries.length;
    await _load(next);
  }

  @override
  Future<void> skipToPrevious() async {
    if (entries.isEmpty) return;
    if (player.position.inSeconds > 3) {
      await seek(Duration.zero);
    } else {
      await _load((index - 1 + entries.length) % entries.length);
    }
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    repeat.value = repeatMode;
    _broadcast();
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    shuffled.value = shuffleMode != AudioServiceShuffleMode.none;
    _broadcast();
  }

  @override
  Future<void> stop() async {
    _loadGeneration++;
    _resumePosition = player.position;
    await player.stop();
    _loaded = false;
    loading.value = false;
    error.value = null;
    _broadcast();
    await super.stop();
  }

  Future<void> clear() async {
    await stop();
    entries = [];
    index = 0;
    queue.add([]);
    mediaItem.add(null);
    _resumePosition = Duration.zero;
    _broadcast();
  }
}
