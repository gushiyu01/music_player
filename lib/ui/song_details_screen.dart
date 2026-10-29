import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/audio_tags.dart';
import '../data/baidu_client.dart';
import '../data/online_catalog.dart';
import '../data/song_details_repository.dart';
import '../main.dart';
import '../models/drive_entry.dart';
import '../models/song_details.dart';
import 'home_screen.dart';

class SongDetailsScreen extends StatefulWidget {
  const SongDetailsScreen({
    super.key,
    required this.controller,
    required this.entry,
  });
  final AppController controller;
  final DriveEntry entry;
  @override
  State<SongDetailsScreen> createState() => _SongDetailsScreenState();
}

class _SongDetailsScreenState extends State<SongDetailsScreen> {
  bool busy = false;
  String? error;
  AppController get app => widget.controller;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _run(Future<void> Function() work) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await work();
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = failure is DriveException
              ? failure.message
              : failure is FormatException
              ? failure.message
              : '资料读取失败，请稍后重试或从手机导入',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _load({bool refresh = false}) => _run(() async {
    await app.details?.load(widget.entry, refresh: refresh);
  });

  Future<void> _import(bool cover) => _run(() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: cover
          ? ['jpg', 'jpeg', 'png', 'webp']
          : ['lrc', 'txt'],
    );
    if (files.isEmpty) return;
    final file = files.first;
    final max = cover ? AudioTags.maxCover : AudioTags.maxLyrics;
    if ((await file.length() ?? max + 1) > max) {
      throw FormatException(cover ? '请选择不超过 5 MB 的图片' : '请选择不超过 256 KB 的歌词');
    }
    final bytes = await SongDetailsRepository.readLimited(
      file.xFile.openRead(),
      max,
    );
    if (cover) {
      await app.details!.setCover(widget.entry, bytes, '手机导入');
    } else {
      await app.details!.setLyrics(
        widget.entry,
        AudioTags.decodeText(bytes),
        '手机导入',
      );
    }
  });

  Future<void> _search(bool cover) async {
    final catalog = app.catalog;
    if (catalog == null) return;
    final details = app.details!.cached(widget.entry);
    final selected = await Navigator.of(context).push<CatalogResult>(
      MaterialPageRoute(
        builder: (_) => CatalogSearchScreen(
          catalog: catalog,
          cover: cover,
          title: details.title ?? widget.entry.title,
          artist: details.artist ?? widget.entry.artist,
        ),
      ),
    );
    if (selected == null || !mounted) return;
    await _run(() async {
      if (cover) {
        await app.details!.setCover(
          widget.entry,
          await catalog.coverBytes(selected),
          'Cover Art Archive · ${selected.artist} · ${selected.album}',
        );
      } else {
        await app.details!.setLyrics(
          widget.entry,
          selected.lyrics!,
          'LRCLIB · ${selected.artist} · ${selected.album}',
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('歌词与封面'),
      actions: [
        IconButton(
          tooltip: '重新读取网盘资料',
          onPressed: busy ? null : () => _load(refresh: true),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: app.details == null
        ? const Center(child: Text('资料缓存尚未初始化'))
        : AnimatedBuilder(
            animation: app.details!,
            builder: (context, _) {
              final details = app.details!.cached(widget.entry);
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    child: Row(
                      children: [
                        CoverTile(
                          seed: widget.entry.id.hashCode,
                          size: 82,
                          imagePath: details.coverPath,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                details.title ?? widget.entry.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                details.artist ?? widget.entry.artist,
                                style: const TextStyle(color: mutedColor),
                              ),
                              if (details.album?.isNotEmpty == true)
                                Text(
                                  details.album!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: mutedColor,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        ActionChip(
                          label: const Text('导入歌词'),
                          onPressed: busy ? null : () => _import(false),
                        ),
                        ActionChip(
                          label: const Text('导入封面'),
                          onPressed: busy ? null : () => _import(true),
                        ),
                        if (app.catalog != null) ...[
                          ActionChip(
                            label: const Text('搜索歌词'),
                            onPressed: busy ? null : () => _search(false),
                          ),
                          ActionChip(
                            label: const Text('搜索封面'),
                            onPressed: busy ? null : () => _search(true),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (busy) const LinearProgressIndicator(),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Color(0xFFFFCF9C)),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      [
                        if (details.lyricsSource != null)
                          '歌词：${details.lyricsSource}',
                        if (details.coverSource != null)
                          '封面：${details.coverSource}',
                        if (details.lyricsSource == null &&
                            details.coverSource == null)
                          '读取同目录文件和常用 MP3 / FLAC 内嵌标签，可导入或手动匹配。',
                      ].join('\n'),
                      style: const TextStyle(fontSize: 11, color: mutedColor),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    child: LyricsPanel(
                      text: details.lyrics ?? '',
                      position: Stream<Duration>.periodic(
                        const Duration(milliseconds: 400),
                        (_) => _isCurrent
                            ? app.audio.currentPosition
                            : Duration.zero,
                      ),
                      onSeek: (position) async {
                        if (_isCurrent) {
                          await app.audio.seek(position);
                        } else {
                          await app.audio.playEntries([widget.entry], 0);
                          await app.audio.seek(position);
                        }
                      },
                    ),
                  ),
                ],
              );
            },
          ),
  );

  bool get _isCurrent =>
      app.audio.entries.isNotEmpty &&
      app.audio.index < app.audio.entries.length &&
      app.audio.entries[app.audio.index].id == widget.entry.id;
}

class LyricsPanel extends StatefulWidget {
  const LyricsPanel({
    super.key,
    required this.text,
    required this.position,
    this.onSeek,
  });
  final String text;
  final Stream<Duration> position;
  final void Function(Duration)? onSeek;
  @override
  State<LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends State<LyricsPanel> {
  final scroll = ScrollController();
  late Lyrics lyrics = Lyrics(widget.text);
  int current = -1;
  @override
  void didUpdateWidget(covariant LyricsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      lyrics = Lyrics(widget.text);
      current = -1;
    }
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.text.trim().isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '暂无歌词\n可添加同名 .lrc、从手机导入，或搜索并选择对应版本。',
            textAlign: TextAlign.center,
            style: TextStyle(color: mutedColor, height: 1.8),
          ),
        ),
      );
    }
    if (lyrics.lines.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: SelectableText(
          widget.text,
          style: const TextStyle(fontSize: 18, height: 1.9),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => StreamBuilder<Duration>(
        stream: widget.position,
        initialData: Duration.zero,
        builder: (context, snapshot) {
          final active = lyrics.activeAt(snapshot.data ?? Duration.zero);
          if (current != active) {
            current = active;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || !scroll.hasClients || active < 0) return;
              final target = (active * 88 - constraints.maxHeight / 2 + 44)
                  .clamp(0, scroll.position.maxScrollExtent)
                  .toDouble();
              unawaited(
                scroll.animateTo(
                  target,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                ),
              );
            });
          }
          return ListView.builder(
            controller: scroll,
            itemExtent: 88,
            itemCount: lyrics.lines.length,
            padding: const EdgeInsets.symmetric(vertical: 16),
            itemBuilder: (_, i) => InkWell(
              onTap: widget.onSeek == null
                  ? null
                  : () => widget.onSeek!(
                      Duration(milliseconds: lyrics.lines[i].milliseconds),
                    ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    lyrics.lines[i].text,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: i == active ? 21 : 17,
                      fontWeight: i == active
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: i == active ? accentColor : mutedColor,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class CatalogSearchScreen extends StatefulWidget {
  const CatalogSearchScreen({
    super.key,
    required this.catalog,
    required this.cover,
    required this.title,
    required this.artist,
  });
  final OnlineCatalog catalog;
  final bool cover;
  final String title, artist;
  @override
  State<CatalogSearchScreen> createState() => _CatalogSearchScreenState();
}

class _CatalogSearchScreenState extends State<CatalogSearchScreen> {
  late final title = TextEditingController(text: widget.title);
  late final artist = TextEditingController(text: widget.artist);
  List<CatalogResult>? results;
  bool busy = false;
  String? error;
  @override
  void dispose() {
    title.dispose();
    artist.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final items = widget.cover
          ? await widget.catalog.covers(title.text, artist.text)
          : await widget.catalog.lyrics(title.text, artist.text);
      if (mounted) setState(() => results = items);
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = failure is DriveException
              ? failure.message
              : '搜索失败，请修改歌名/歌手或稍后重试',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.cover ? '匹配封面' : '匹配歌词')),
    body: CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text(
                  widget.cover
                      ? '通过 MusicBrainz / Cover Art Archive 搜索。'
                      : '通过 LRCLIB 搜索。',
                ),
                const Text(
                  '只发送下面的歌名和歌手，不发送网盘凭据。请选择正确版本。',
                  style: TextStyle(color: mutedColor, fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: '歌名'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: artist,
                  decoration: const InputDecoration(labelText: '歌手（可修改）'),
                  onSubmitted: (_) => _search(),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: busy ? null : _search,
                  icon: const Icon(Icons.search),
                  label: const Text('搜索候选'),
                ),
                if (error != null)
                  Text(
                    error!,
                    style: const TextStyle(color: Color(0xFFFFCF9C)),
                  ),
              ],
            ),
          ),
        ),
        if (busy) const SliverToBoxAdapter(child: LinearProgressIndicator()),
        SliverList.list(
          children: [
            if (results?.isEmpty == true)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('没有找到对应版本，可修改关键词或从手机导入。'),
              ),
            for (final result in results ?? <CatalogResult>[])
              ListTile(
                title: Text(result.title),
                subtitle: Text(
                  '${result.artist}\n${result.album}${result.duration == null ? '' : ' · ${result.duration! ~/ 60}:${(result.duration! % 60).toString().padLeft(2, '0')}'}',
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.check_circle_outline),
                onTap: () => Navigator.pop(context, result),
              ),
          ],
        ),
      ],
    ),
  );
}
