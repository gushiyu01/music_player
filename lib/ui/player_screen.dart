import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../main.dart';
import 'home_screen.dart';

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key, required this.controller});
  final AppController controller;

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
      leading: IconButton(
        tooltip: '收起播放器',
        icon: const Icon(Icons.keyboard_arrow_down),
        onPressed: () => Navigator.pop(context),
      ),
      title: const Text(
        '正在播放',
        style: TextStyle(fontSize: 14, letterSpacing: 3),
      ),
      centerTitle: true,
      actions: [
        IconButton(
          tooltip: '播放队列',
          onPressed: () => _queue(context),
          icon: const Icon(Icons.queue_music),
        ),
      ],
    ),
    body: SafeArea(
      child: StreamBuilder<MediaItem?>(
        stream: controller.audio.mediaItem,
        builder: (context, snapshot) {
          final item = snapshot.data;
          if (item == null) return const Center(child: Text('从音乐库选择一首歌'));
          final audio = controller.audio;
          return ListView(
            padding: const EdgeInsets.fromLTRB(30, 28, 30, 20),
            children: [
              Center(
                child: LayoutBuilder(
                  builder: (_, constraints) => CoverTile(
                    seed: item.id.hashCode,
                    size: constraints.maxWidth.clamp(180, 340),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                item.artist ?? '百度网盘',
                style: const TextStyle(color: mutedColor, fontSize: 14),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    item.extras?['source'] == 'local'
                        ? Icons.offline_pin_outlined
                        : Icons.cloud_outlined,
                    size: 16,
                    color: accentColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    item.extras?['source'] == 'local'
                        ? '本地文件 · 离线播放'
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
                          saved ? Icons.download_done : Icons.download_outlined,
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 26),
              StreamBuilder<Duration>(
                stream: audio.player.positionStream,
                initialData: Duration.zero,
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
              const SizedBox(height: 24),
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
                        width: 76,
                        height: 76,
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
              const SizedBox(height: 26),
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
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_outlined, size: 14, color: mutedColor),
                  const SizedBox(width: 8),
                  Text(
                    item.id.startsWith('demo-') ? '原创合成音频 · 离线试听' : '手机直连百度网盘',
                    style: const TextStyle(fontSize: 11, color: mutedColor),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    ),
  );

  String _time(Duration duration) =>
      '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';
}
