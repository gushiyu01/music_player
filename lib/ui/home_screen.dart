import 'dart:async';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../main.dart';
import 'connection_screen.dart';
import 'player_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});
  final AppController controller;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _search = TextEditingController();
  bool _onlyFavorites = false;
  AppController get app => widget.controller;
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ConnectionScreen(controller: app)),
    );
    if (result == true) {
      await app.audio.clear();
      await app.browse('/');
    }
    if (mounted) setState(() {});
  }

  Future<void> _navigate(String path) async {
    _search.clear();
    await app.browse(path);
  }

  void _openPlayer() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => PlayerScreen(controller: app)));
  }

  Future<void> _chooseDirectory() async {
    final input = TextEditingController(text: app.demo ? '/' : app.directory);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('打开音乐目录'),
        content: TextField(
          controller: input,
          autofocus: true,
          decoration: const InputDecoration(hintText: '/音乐'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text),
            child: const Text('打开'),
          ),
        ],
      ),
    );
    if (value != null && value.trim().isNotEmpty) await _navigate(value.trim());
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: app,
    builder: (context, _) {
      final entries = app.visible
          .where(
            (e) => !_onlyFavorites || (!e.isDirectory && app.isFavorite(e)),
          )
          .toList();
      final tracks = entries.where((e) => e.isAudio).toList();
      return Scaffold(
        appBar: AppBar(
          toolbarHeight: 78,
          title: const Row(
            children: [
              Icon(Icons.graphic_eq, color: accentColor),
              SizedBox(width: 10),
              Text(
                '云间',
                style: TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: '连接设置',
              onPressed: _connect,
              icon: Icon(
                app.connected
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_outlined,
              ),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  if (!app.demo) await app.browse(app.directory);
                },
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: app.demo ? mutedColor : accentColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  app.demo ? '离线试听 · 随时开始' : '百度网盘直连 · 仅在本机',
                                  style: const TextStyle(
                                    color: mutedColor,
                                    fontSize: 12,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 22),
                            const Text(
                              '让收藏，\n重新被听见。',
                              style: TextStyle(
                                fontSize: 34,
                                height: 1.35,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(height: 22),
                            TextField(
                              controller: _search,
                              onChanged: app.search,
                              decoration: InputDecoration(
                                hintText: '搜索当前目录的音乐',
                                prefixIcon: const Icon(
                                  Icons.search,
                                  color: mutedColor,
                                ),
                                suffixIcon: app.query.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: '清除搜索',
                                        onPressed: () {
                                          _search.clear();
                                          app.search('');
                                        },
                                        icon: const Icon(Icons.close),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (app.demo)
                              Container(
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF242F22),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Row(
                                  children: [
                                    const Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '你的网盘，就是音乐库',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          SizedBox(height: 6),
                                          Text(
                                            '先听两段原创旋律，或连接自己的网盘',
                                            style: TextStyle(
                                              color: mutedColor,
                                              fontSize: 12,
                                              height: 1.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton.filled(
                                      tooltip: app.connected ? '浏览网盘' : '连接网盘',
                                      onPressed: app.connected
                                          ? () => _navigate('/')
                                          : _connect,
                                      icon: const Icon(Icons.arrow_forward),
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                ChoiceChip(
                                  label: const Text('全部音乐'),
                                  selected: !_onlyFavorites,
                                  onSelected: (_) =>
                                      setState(() => _onlyFavorites = false),
                                ),
                                const SizedBox(width: 8),
                                ChoiceChip(
                                  label: const Text('喜欢'),
                                  selected: _onlyFavorites,
                                  onSelected: (_) =>
                                      setState(() => _onlyFavorites = true),
                                ),
                                const Spacer(),
                                if (tracks.isNotEmpty)
                                  IconButton(
                                    tooltip: '播放当前列表',
                                    onPressed: () => unawaited(
                                      app.audio.playEntries(tracks, 0),
                                    ),
                                    icon: const Icon(
                                      Icons.play_circle_fill,
                                      color: accentColor,
                                      size: 32,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap: app.connected
                                        ? _chooseDirectory
                                        : null,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      child: Text(
                                        app.demo
                                            ? 'DEMO / 原创试听'
                                            : app.directory,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: mutedColor,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                if (!app.demo && app.directory != '/')
                                  IconButton(
                                    tooltip: '返回上级目录',
                                    onPressed: () {
                                      final parent = app.directory.substring(
                                        0,
                                        app.directory.lastIndexOf('/'),
                                      );
                                      unawaited(
                                        _navigate(
                                          parent.isEmpty ? '/' : parent,
                                        ),
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.drive_folder_upload_outlined,
                                      size: 20,
                                    ),
                                  ),
                                if (!app.demo)
                                  IconButton(
                                    tooltip: '刷新目录',
                                    onPressed: app.busy
                                        ? null
                                        : () => _navigate(app.directory),
                                    icon: const Icon(Icons.refresh, size: 20),
                                  ),
                              ],
                            ),
                            if (app.error != null)
                              Container(
                                margin: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF352820),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      app.error!,
                                      style: const TextStyle(
                                        color: Color(0xFFFFCF9C),
                                        height: 1.5,
                                      ),
                                    ),
                                    Wrap(
                                      children: [
                                        TextButton(
                                          onPressed: () => app.browse(
                                            app.directory,
                                            more: app.nextStart != null,
                                          ),
                                          child: const Text('重试'),
                                        ),
                                        TextButton(
                                          onPressed: _connect,
                                          child: const Text('连接设置'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (app.busy && entries.isEmpty)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(36),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      ),
                    if (!app.busy && entries.isEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.library_music_outlined,
                                size: 44,
                                color: mutedColor,
                              ),
                              const SizedBox(height: 14),
                              Text(
                                _onlyFavorites
                                    ? '还没有喜欢的歌曲'
                                    : app.query.isNotEmpty
                                    ? '当前已加载的列表中没有匹配音乐'
                                    : '这个目录还没有可播放的音乐',
                                style: const TextStyle(
                                  color: mutedColor,
                                  height: 1.7,
                                ),
                              ),
                              if (!app.demo)
                                TextButton(
                                  onPressed: _chooseDirectory,
                                  child: const Text('打开其他目录'),
                                ),
                            ],
                          ),
                        ),
                      ),
                    SliverList.builder(
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 2,
                          ),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            leading: entry.isDirectory
                                ? Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: surfaceColor,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.folder_outlined,
                                      color: accentColor,
                                    ),
                                  )
                                : CoverTile(seed: entry.id.hashCode, size: 48),
                            title: Text(
                              entry.isDirectory ? entry.name : entry.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              entry.isDirectory
                                  ? '文件夹'
                                  : entry.demo
                                  ? '原创合成试听 · WAV'
                                  : '${entry.extension.toUpperCase()} · ${_size(entry.size)}',
                              style: const TextStyle(
                                color: mutedColor,
                                fontSize: 11,
                              ),
                            ),
                            trailing: entry.isDirectory
                                ? const Icon(
                                    Icons.chevron_right,
                                    color: mutedColor,
                                  )
                                : IconButton(
                                    tooltip: app.isFavorite(entry)
                                        ? '取消喜欢'
                                        : '喜欢这首歌',
                                    onPressed: () => app.toggleFavorite(entry),
                                    icon: Icon(
                                      app.isFavorite(entry)
                                          ? Icons.favorite
                                          : Icons.favorite_border,
                                      color: app.isFavorite(entry)
                                          ? accentColor
                                          : mutedColor,
                                      size: 20,
                                    ),
                                  ),
                            onTap: () {
                              if (entry.isDirectory) {
                                unawaited(_navigate(entry.path));
                              } else {
                                unawaited(
                                  app.audio.playEntries(
                                    tracks,
                                    tracks.indexOf(entry),
                                  ),
                                );
                              }
                            },
                          ),
                        );
                      },
                    ),
                    if (app.nextStart != null)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: OutlinedButton(
                            onPressed: app.busy
                                ? null
                                : () => app.browse(app.directory, more: true),
                            child: Text(app.busy ? '正在加载…' : '加载更多文件'),
                          ),
                        ),
                      ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Text(
                            app.demo
                                ? '给自己的音乐，留一点时间。'
                                : '已加载 ${app.entries.where((e) => e.isAudio).length} 首音乐${app.nextStart != null ? ' · 还有更多文件' : ''}',
                            style: const TextStyle(
                              color: mutedColor,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _MiniPlayer(controller: app, open: _openPlayer),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    TextButton.icon(
                      onPressed: () => setState(() => _onlyFavorites = false),
                      icon: const Icon(Icons.library_music_outlined, size: 21),
                      label: const Text('音乐库'),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        app.useDemo();
                        _search.clear();
                        setState(() => _onlyFavorites = false);
                      },
                      icon: const Icon(Icons.headphones_outlined, size: 21),
                      label: const Text('试听'),
                    ),
                    TextButton.icon(
                      onPressed: _connect,
                      icon: const Icon(Icons.tune, size: 21),
                      label: const Text('连接'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  String _size(int bytes) =>
      bytes <= 0 ? '大小未知' : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

class CoverTile extends StatelessWidget {
  const CoverTile({super.key, required this.seed, this.size = 56});
  final int seed;
  final double size;
  @override
  Widget build(BuildContext context) {
    final colors = [
      const Color(0xFF4B6550),
      const Color(0xFF5D6950),
      const Color(0xFF506165),
      const Color(0xFF6E6050),
    ];
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors[seed.abs() % colors.length],
        borderRadius: BorderRadius.circular(size * .23),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            right: -size * .25,
            bottom: -size * .2,
            child: Container(
              width: size * 1.1,
              height: size * 1.1,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: .12),
                  width: size * .08,
                ),
              ),
            ),
          ),
          Icon(
            Icons.graphic_eq,
            color: const Color(0xFFE4EDD9),
            size: size * .4,
          ),
        ],
      ),
    );
  }
}

class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer({required this.controller, required this.open});
  final AppController controller;
  final VoidCallback open;
  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: controller.audio.mediaItem,
    builder: (context, snapshot) {
      final item = snapshot.data;
      if (item == null) return const SizedBox.shrink();
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        decoration: BoxDecoration(
          color: const Color(0xFF293428),
          borderRadius: BorderRadius.circular(18),
        ),
        child: ListTile(
          onTap: open,
          leading: CoverTile(seed: item.id.hashCode, size: 42),
          title: Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          subtitle: ValueListenableBuilder(
            valueListenable: controller.audio.error,
            builder: (_, error, _) => Text(
              error == null ? item.artist ?? '百度网盘' : '播放中断 · 点击查看',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: mutedColor),
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StreamBuilder(
                stream: controller.audio.playbackState,
                builder: (_, snapshot) => IconButton(
                  tooltip: snapshot.data?.playing == true ? '暂停' : '播放',
                  onPressed: () {
                    if (snapshot.data?.playing == true) {
                      unawaited(controller.audio.pause());
                    } else {
                      unawaited(controller.audio.play());
                    }
                  },
                  icon: Icon(
                    snapshot.data?.playing == true
                        ? Icons.pause
                        : Icons.play_arrow,
                  ),
                ),
              ),
              IconButton(
                tooltip: '下一首',
                onPressed: controller.audio.skipToNext,
                icon: const Icon(Icons.skip_next),
              ),
            ],
          ),
        ),
      );
    },
  );
}
