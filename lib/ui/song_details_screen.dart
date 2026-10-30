import 'dart:async';

import 'package:flutter/material.dart';

import '../data/baidu_client.dart';
import '../data/online_catalog.dart';
import '../main.dart';
import '../models/song_details.dart';

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
            '暂无歌词\n可在左上角搜索歌词，或读取歌曲同目录的 .lrc。',
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
    required this.onApply,
  });
  final OnlineCatalog catalog;
  final bool cover;
  final String title, artist;
  final Future<void> Function(CatalogResult) onApply;
  @override
  State<CatalogSearchScreen> createState() => _CatalogSearchScreenState();
}

class _CatalogSearchScreenState extends State<CatalogSearchScreen> {
  late final title = TextEditingController(text: widget.title);
  late final artist = TextEditingController(text: widget.artist);
  List<CatalogResult>? results;
  bool busy = false;
  String? error;
  String? applying;
  DateTime? retryAt;
  Timer? countdown;
  int get remaining => retryAt == null
      ? 0
      : ((retryAt!.difference(DateTime.now()).inMilliseconds / 1000).ceil())
            .clamp(0, 3600);
  @override
  void dispose() {
    countdown?.cancel();
    title.dispose();
    artist.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (busy || applying != null || remaining > 0) return;
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
      results = null;
    });
    try {
      final items = widget.cover
          ? await widget.catalog.covers(title.text, artist.text)
          : await widget.catalog.lyrics(title.text, artist.text);
      if (mounted) setState(() => results = items);
    } catch (failure) {
      if (mounted) {
        _failure(failure);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _failure(Object failure) {
    setState(() {
      error = failure is DriveException
          ? failure.message
          : failure is FormatException
          ? failure.message
          : '资料读取失败，请检查网络后重试';
      if (failure is CatalogException && failure.retryAfter != null) {
        retryAt = DateTime.now().add(failure.retryAfter!);
        countdown?.cancel();
        countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) {
            timer.cancel();
            return;
          }
          setState(() {});
          if (remaining == 0) timer.cancel();
        });
      }
    });
  }

  Future<void> _apply(CatalogResult result) async {
    if (busy || applying != null || remaining > 0) return;
    setState(() {
      applying = result.id;
      error = null;
    });
    try {
      await widget.onApply(result);
      if (mounted) Navigator.pop(context, true);
    } catch (failure) {
      if (mounted) _failure(failure);
    } finally {
      if (mounted) setState(() => applying = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.cover ? '搜索封面' : '搜索歌词')),
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
                  onPressed: busy || applying != null || remaining > 0
                      ? null
                      : _search,
                  icon: const Icon(Icons.search),
                  label: Text(
                    remaining > 0
                        ? '$remaining 秒后重试'
                        : busy
                        ? '正在搜索…'
                        : results == null && error != null
                        ? '重新搜索'
                        : '搜索候选',
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      error!,
                      style: const TextStyle(color: Color(0xFFFFCF9C)),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (busy || applying != null)
          const SliverToBoxAdapter(child: LinearProgressIndicator()),
        SliverList.list(
          children: [
            if (results?.isEmpty == true)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('没有找到对应版本，请尝试仅填歌名，或换用简体/繁体关键词。'),
              ),
            for (final result in results ?? <CatalogResult>[])
              ListTile(
                title: Text(result.title),
                subtitle: Text(
                  '${result.artist}\n${result.album}${result.duration == null ? '' : ' · ${result.duration! ~/ 60}:${(result.duration! % 60).toString().padLeft(2, '0')}'}',
                ),
                isThreeLine: true,
                trailing: applying == result.id
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                enabled: !busy && applying == null && remaining == 0,
                onTap: () => _apply(result),
              ),
          ],
        ),
      ],
    ),
  );
}
