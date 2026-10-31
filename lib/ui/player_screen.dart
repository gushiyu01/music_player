import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../main.dart';
import '../models/drive_entry.dart';
import '../models/song_details.dart';
import '../models/catalog_query.dart';
import 'home_screen.dart';
import 'song_actions.dart';
import 'song_details_screen.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.controller,
    this.initialPage = 0,
  });
  final AppController controller;
  final int initialPage;
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  AppController get controller => widget.controller;
  late final pages = PageController(initialPage: widget.initialPage);
  late int page = widget.initialPage;
  final positions = StreamController<Duration>.broadcast();
  late final Timer positionTimer;
  Duration? lastPosition;
  @override
  void initState() {
    super.initState();
    positionTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      final position = controller.audio.currentPosition;
      if (position == lastPosition) return;
      lastPosition = position;
      positions.add(position);
    });
  }

  @override
  void dispose() {
    positionTimer.cancel();
    unawaited(positions.close());
    pages.dispose();
    super.dispose();
  }

  DriveEntry? get current {
    final audio = controller.audio;
    return audio.entries.isEmpty || audio.index >= audio.entries.length
        ? null
        : audio.entries[audio.index];
  }

  Future<void> _search(bool cover) async {
    final entry = current;
    final catalog = controller.catalog;
    final repository = controller.details;
    if (entry == null || catalog == null || repository == null) return;
    final terms = CatalogQuery.fromSong(
      entry,
      repository.cached(entry),
      controller.musicRoot,
    );
    final applied = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CatalogSearchScreen(
          catalog: catalog,
          cover: cover,
          title: terms.title,
          artist: terms.artist,
          onApply: (selected) async {
            if (cover) {
              await repository.setCover(
                entry,
                await catalog.coverBytes(selected),
                'Cover Art Archive · ${selected.artist} · ${selected.album}',
              );
            } else {
              await repository.setLyrics(
                entry,
                selected.lyrics!,
                'LRCLIB · ${selected.artist} · ${selected.album}',
              );
            }
          },
        ),
      ),
    );
    if (!mounted ||
        applied != true ||
        current?.id != entry.id ||
        current?.path != entry.path) {
      return;
    }
    await pages.animateToPage(
      cover ? 0 : 1,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _queue(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: StreamBuilder(
        stream: controller.audio.queue,
        builder: (context, snapshot) {
          final items = snapshot.data ?? [];
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  '接下来播放',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (_, index) => ListTile(
                    leading: Icon(
                      index == controller.audio.index
                          ? Icons.graphic_eq
                          : Icons.music_note_outlined,
                      color: index == controller.audio.index
                          ? accentColor
                          : mutedColor,
                    ),
                    title: Text(
                      items[index].title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () {
                      unawaited(controller.audio.skipToQueueItem(index));
                      Navigator.pop(context);
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: PopupMenuButton<bool>(
        tooltip: '搜索歌词或封面',
        enabled: controller.catalog != null && controller.details != null,
        icon: const Icon(Icons.search),
        onSelected: _search,
        itemBuilder: (_) => const [
          PopupMenuItem(value: false, child: Text('搜索歌词')),
          PopupMenuItem(value: true, child: Text('搜索封面')),
        ],
      ),
      title: const Text(
        '正在播放',
        style: TextStyle(fontSize: 14, letterSpacing: 3),
      ),
      centerTitle: true,
      actions: [
        StreamBuilder<MediaItem?>(
          stream: controller.audio.mediaItem,
          builder: (_, _) {
            final entry = current;
            if (entry == null || !controller.canManage(entry)) {
              return const SizedBox.shrink();
            }
            return PopupMenuButton<bool>(
              tooltip: '当前歌曲操作',
              onSelected: (deleting) =>
                  manageSong(context, controller, entry, deleting: deleting),
              itemBuilder: (_) => const [
                PopupMenuItem(value: false, child: Text('移动到其他目录')),
                PopupMenuItem(value: true, child: Text('删除网盘文件')),
              ],
            );
          },
        ),
        IconButton(
          tooltip: '播放队列',
          onPressed: () => _queue(context),
          icon: const Icon(Icons.queue_music),
        ),
        IconButton(
          tooltip: '收起播放器',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.keyboard_arrow_down),
        ),
      ],
    ),
    body: SafeArea(
      child: AnimatedBuilder(
        animation: controller,
        builder: (_, _) => StreamBuilder<MediaItem?>(
          stream: controller.audio.mediaItem,
          builder: (context, snapshot) {
            final item = snapshot.data;
            if (item == null) return const Center(child: Text('从音乐库选择一首歌'));
            final audio = controller.audio;
            final entry = current;
            final details = entry == null
                ? const SongDetails()
                : controller.details?.cached(entry) ?? const SongDetails();
            return LayoutBuilder(
              builder: (context, constraints) => ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                children: [
                  SizedBox(
                    height: (constraints.maxHeight - 414).clamp(180.0, 440.0),
                    child: PageView(
                      key: const Key('player-pages'),
                      controller: pages,
                      onPageChanged: (value) => setState(() => page = value),
                      children: [
                        Semantics(
                          label: '歌曲封面',
                          child: Center(
                            child: LayoutBuilder(
                              builder: (_, box) => CoverTile(
                                seed: item.id.hashCode,
                                imagePath:
                                    details.coverPath ??
                                    item.artUri?.toFilePath(),
                                size:
                                    (box.maxWidth < box.maxHeight
                                            ? box.maxWidth
                                            : box.maxHeight)
                                        .clamp(120, 340),
                              ),
                            ),
                          ),
                        ),
                        LyricsPanel(
                          key: ValueKey('lyrics:${entry?.id}:${entry?.path}'),
                          text: details.lyrics ?? '',
                          position: positions.stream,
                          initialPosition: audio.currentPosition,
                          onSeek: (position) => unawaited(audio.seek(position)),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < 2; i++)
                        TextButton(
                          onPressed: () => pages.animateToPage(
                            i,
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOut,
                          ),
                          child: Text(
                            i == 0 ? '封面' : '歌词',
                            style: TextStyle(
                              fontSize: 12,
                              color: page == i ? accentColor : mutedColor,
                              fontWeight: page == i
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.artist ?? '百度网盘',
                    style: const TextStyle(color: mutedColor, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        item.extras?['source'] == 'local' ||
                                item.extras?['source'] == 'cache'
                            ? Icons.offline_pin_outlined
                            : Icons.cloud_outlined,
                        size: 16,
                        color: accentColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        item.extras?['source'] == 'local'
                            ? '本地文件 · 离线播放'
                            : item.extras?['source'] == 'cache'
                            ? '歌曲缓存 · 离线播放'
                            : item.extras?['source'] == 'demo'
                            ? '原创试听'
                            : '在线播放',
                        style: const TextStyle(color: mutedColor, fontSize: 12),
                      ),
                      const Spacer(),
                      AnimatedBuilder(
                        animation: controller,
                        builder: (_, _) {
                          if (audio.entries.isEmpty ||
                              controller.transfers == null) {
                            return const SizedBox.shrink();
                          }
                          final entry = audio.entries[audio.index];
                          final saved =
                              controller.library?.localPath(entry) != null;
                          return IconButton(
                            tooltip: saved ? '已下载到本地' : '下载当前歌曲',
                            onPressed: saved
                                ? null
                                : () {
                                    controller.transfers!.download(entry);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('已加入下载任务')),
                                    );
                                  },
                            icon: Icon(
                              saved
                                  ? Icons.download_done
                                  : Icons.download_outlined,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  StreamBuilder<Duration>(
                    stream: positions.stream,
                    initialData: audio.currentPosition,
                    builder: (context, snapshot) {
                      final duration = item.duration ?? Duration.zero;
                      final position = snapshot.data ?? Duration.zero;
                      final max = duration.inMilliseconds.toDouble();
                      return Column(
                        children: [
                          Slider(
                            padding: EdgeInsets.zero,
                            value: position.inMilliseconds.toDouble().clamp(
                              0,
                              max > 0 ? max : 1,
                            ),
                            max: max > 0 ? max : 1,
                            onChanged: max > 0
                                ? (value) => unawaited(
                                    audio.seek(
                                      Duration(milliseconds: value.round()),
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _time(position),
                                style: const TextStyle(
                                  color: mutedColor,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                _time(duration),
                                style: const TextStyle(
                                  color: mutedColor,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ValueListenableBuilder(
                        valueListenable: audio.shuffled,
                        builder: (_, shuffled, _) => IconButton(
                          tooltip: shuffled ? '关闭随机' : '随机播放',
                          onPressed: () => audio.setShuffleMode(
                            shuffled
                                ? AudioServiceShuffleMode.none
                                : AudioServiceShuffleMode.all,
                          ),
                          icon: Icon(
                            Icons.shuffle,
                            color: shuffled ? accentColor : mutedColor,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '上一首',
                        onPressed: audio.skipToPrevious,
                        iconSize: 34,
                        icon: const Icon(Icons.skip_previous),
                      ),
                      StreamBuilder(
                        stream: audio.playbackState,
                        builder: (_, state) => ValueListenableBuilder(
                          valueListenable: audio.loading,
                          builder: (_, loading, _) => SizedBox(
                            width: 68,
                            height: 68,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                padding: EdgeInsets.zero,
                                shape: const CircleBorder(),
                              ),
                              onPressed: loading
                                  ? null
                                  : () {
                                      if (state.data?.playing == true) {
                                        unawaited(audio.pause());
                                      } else {
                                        unawaited(audio.play());
                                      }
                                    },
                              child: loading
                                  ? const SizedBox(
                                      width: 26,
                                      height: 26,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Icon(
                                      state.data?.playing == true
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                      size: 42,
                                    ),
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '下一首',
                        onPressed: audio.skipToNext,
                        iconSize: 34,
                        icon: const Icon(Icons.skip_next),
                      ),
                      ValueListenableBuilder(
                        valueListenable: audio.repeat,
                        builder: (_, mode, _) => IconButton(
                          tooltip: '切换循环模式',
                          onPressed: () => audio.setRepeatMode(
                            mode == AudioServiceRepeatMode.none
                                ? AudioServiceRepeatMode.all
                                : mode == AudioServiceRepeatMode.all
                                ? AudioServiceRepeatMode.one
                                : AudioServiceRepeatMode.none,
                          ),
                          icon: Icon(
                            mode == AudioServiceRepeatMode.one
                                ? Icons.repeat_one
                                : Icons.repeat,
                            color: mode == AudioServiceRepeatMode.none
                                ? mutedColor
                                : accentColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ValueListenableBuilder(
                    valueListenable: audio.error,
                    builder: (_, error, _) => error == null
                        ? const SizedBox.shrink()
                        : Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF352820),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  error,
                                  style: const TextStyle(
                                    color: Color(0xFFFFCF9C),
                                    height: 1.6,
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: audio.play,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('重新获取链接并播放'),
                                ),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );

  String _time(Duration duration) =>
      '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';
}
