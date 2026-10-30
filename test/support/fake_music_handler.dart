import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:music_player/models/drive_entry.dart';
import 'package:music_player/playback/music_handler.dart';

class FakeMusicHandler extends BaseAudioHandler implements MusicHandler {
  @override
  final error = ValueNotifier<String?>(null);
  @override
  final loading = ValueNotifier(false);
  @override
  final shuffled = ValueNotifier(false);
  @override
  final repeat = ValueNotifier(AudioServiceRepeatMode.none);
  Duration position = Duration.zero;
  List<DriveEntry> selected = [];
  @override
  List<DriveEntry> get entries => selected;
  @override
  int index = 0;
  @override
  Duration get currentPosition => position;
  @override
  Future<void> seek(Duration value) async => position = value;
  @override
  Future<void> clear() async => selected = [];
  @override
  Future<void> removeEntry(DriveEntry entry) async {
    selected = selected.where((e) => e.id != entry.id).toList();
  }

  @override
  void replaceEntry(DriveEntry old, DriveEntry replacement) {
    selected = [
      for (final entry in selected)
        if (entry.id == old.id) replacement else entry,
    ];
  }

  @override
  void restore(List<DriveEntry> tracks, int current, Duration position) {
    selected = tracks;
    index = tracks.isEmpty ? 0 : current.clamp(0, tracks.length - 1);
  }

  @override
  Future<void> playEntries(
    List<DriveEntry> tracks,
    int current, {
    bool onlineOnly = false,
  }) async {
    selected = tracks;
    index = current;
    queue.add([
      for (final entry in tracks)
        MediaItem(
          id: entry.id,
          title: entry.title,
          artist: entry.artist,
          duration: const Duration(minutes: 4),
        ),
    ]);
    mediaItem.add(queue.value[index]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
