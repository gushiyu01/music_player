import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:music_player/models/drive_entry.dart';
import 'package:music_player/playback/music_handler.dart';

class FakeMusicHandler extends BaseAudioHandler implements MusicHandler {
  @override
  final error = ValueNotifier<String?>(null);
  List<DriveEntry> selected = [];
  @override
  List<DriveEntry> get entries => selected;
  @override
  int index = 0;
  @override
  Duration get currentPosition => Duration.zero;
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
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
