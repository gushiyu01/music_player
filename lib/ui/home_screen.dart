import 'dart:async';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../app_controller.dart';
import '../main.dart';
import '../models/drive_entry.dart';
import '../data/baidu_client.dart';
import 'transfers_screen.dart';
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
    if (app.local) {
      app.showLocal(path);
    } else {
      await app.browse(path);
    }
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _transfers() {
    final manager = app.transfers;
    if (manager != null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TransfersScreen(manager: manager)),
      );
    }
  }

  Future<void> _upload() async {
    final destination = app.directory;
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'mp3',
          'flac',
          'm4a',
          'aac',
          'wav',
          'ogg',
          'opus',
          'aiff',
          'aif',
          'amr',
        ],
      );
      if (!mounted || files.isEmpty) return;
      var added = 0;
      for (final file in files) {
        final entry = DriveEntry(id: '', name: file.name, path: '');
        if (!entry.isAudio) continue;
        final size = await file.length();
        if (size == null || size <= 0 || size > BaiduUpload.maxUploadSize) {
          continue;
        }
        final selected = file.xFile;
        app.transfers?.upload(
          UploadInput(
            name: file.name,
            size: size,
            read: (start, end) => selected.openRead(start, end),
          ),
          destination,
        );
        added++;
      }
      _message(
        added == 0 ? '请选择不超过 2 GB 的音乐文件' : '已添加 $added 首，上传到 $destination',
      );
      if (added > 0 && mounted) _transfers();
    } catch (_) {
      _message('无法读取所选文件，请重新选择手机中的音乐');
    }
  }

  Future<void> _createFolder() async {
    final input = TextEditingController();
    final destination = app.directory;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建歌手目录'),
        content: TextField(
          controller: input,
          autofocus: true,
          decoration: const InputDecoration(hintText: '例如：五月天'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    try {
      await app.client.createFolder(destination, name);
      if (!app.local && app.directory == destination) {
        await app.browse(destination);
      }
      _message('目录已创建');
    } catch (e) {
      _message(e is DriveException ? e.message : '创建目录失败，请重试');
    }
  }

  Future<void> _trackAction(DriveEntry entry, String action) async {
    switch (action) {
      case 'download':
        app.transfers?.download(entry);
        _message('已加入下载任务');
      case 'online':
        await app.audio.playEntries([entry], 0, onlineOnly: true);
      case 'remove':
        try {
          if (app.audio.entries.any((e) => e.id == entry.id)) {
            await app.audio.clear();
          }
          await app.library?.remove(entry);
          _message('已移除本地下载');
        } catch (_) {
          _message('无法移除本地文件，请重试');
        }
    }
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
      final folders = entries.where((e) => e.isDirectory).toList();
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
            if (app.transfers != null)
              IconButton(
                tooltip: '传输任务',
                onPressed: _transfers,
                icon: Badge(
                  isLabelVisible: app.transfers!.activeCount > 0,
                  label: Text('${app.transfers!.activeCount}'),
                  child: const Icon(Icons.swap_vert),
                ),
              ),
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
                  if (!app.demo && !app.local) await app.browse(app.directory);
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
                                  app.local
                                      ? '本地下载 · 断网也能听'
                                      : app.demo
                                      ? '离线试听 · 随时开始'
                                      : '百度网盘直连 · 仅在本机',
                                  style: const TextStyle(
                                    color: mutedColor,
                                    fontSize: 12,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 22),
                            Text(
                              app.local
                                  ? '把喜欢的歌，\n留在身边。'
                                  : !app.demo && app.directory == app.musicRoot
                                  ? '按歌手收藏，\n随心听见。'
                                  : '让收藏，\n重新被听见。',
                              style: const TextStyle(
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
                                hintText: app.local
                                    ? app.localDirectory == null
                                          ? '搜索已下载的目录'
                                          : '搜索当前目录的音乐'
                                    : '搜索当前目录的歌手或音乐',
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
                            if (app.demo && !app.local)
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
                            if (!app.demo && !app.local) ...[
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  FilledButton.tonalIcon(
                                    onPressed: app.busy ? null : _upload,
                                    icon: const Icon(
                                      Icons.upload_outlined,
                                      size: 18,
                                    ),
                                    label: const Text('上传到此目录'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: app.busy ? null : _createFolder,
                                    icon: const Icon(
                                      Icons.create_new_folder_outlined,
                                      size: 18,
                                    ),
                                    label: const Text('新建歌手目录'),
                                  ),
                                ],
                              ),
                            ],
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
                                    onTap: app.connected && !app.local
                                        ? _chooseDirectory
                                        : null,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      child: Text(
                                        app.local
                                            ? app.localDirectory ==
                                                      'assets/audio'
                                                  ? '本地下载 / 原创试听'
                                                  : (app.localDirectory ??
                                                        '本地下载 / 按目录收藏')
                                            : app.demo
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
                                if (app.local && app.localDirectory != null)
                                  IconButton(
                                    tooltip: '返回本地目录',
                                    onPressed: () {
                                      app.showLocal();
                                      _search.clear();
                                    },
                                    icon: const Icon(
                                      Icons.arrow_upward,
                                      size: 20,
                                    ),
                                  ),
                                if (!app.demo &&
                                    !app.local &&
                                    app.directory != '/')
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
                                if (!app.demo && !app.local)
                                  IconButton(
                                    tooltip: '刷新目录',
                                    onPressed: app.busy
                                        ? null
                                        : () => _navigate(app.directory),
                                    icon: const Icon(Icons.refresh, size: 20),
                                  ),
                                if (!app.demo && !app.local)
                                  PopupMenuButton<String>(
                                    tooltip: '目录设置',
                                    onSelected: (value) async {
                                      if (value == 'root') {
                                        await app.setMusicRoot();
                                        _message('已设为音乐库根目录');
                                      }
                                      if (value == 'open') {
                                        await _chooseDirectory();
                                      }
                                      if (value == 'demo') {
                                        app.useDemo();
                                        _search.clear();
                                      }
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(
                                        value: 'root',
                                        child: Text('将此目录设为音乐库'),
                                      ),
                                      PopupMenuItem(
                                        value: 'open',
                                        child: Text('输入网盘目录路径'),
                                      ),
                                      PopupMenuItem(
                                        value: 'demo',
                                        child: Text('原创试听'),
                                      ),
                                    ],
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
                                    : app.local
                                    ? '还没有本地音乐，去音乐库下载几首吧'
                                    : '这个目录还没有可播放的音乐',
                                style: const TextStyle(
                                  color: mutedColor,
                                  height: 1.7,
                                ),
                              ),
                              if (!app.demo && !app.local)
                                TextButton(
                                  onPressed: _chooseDirectory,
                                  child: const Text('打开其他目录'),
                                ),
                            ],
                          ),
                        ),
                      ),
                    if (folders.isNotEmpty)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                        sliver: SliverGrid.builder(
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 240,
                                mainAxisExtent: 112,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                          itemCount: folders.length,
                          itemBuilder: (context, index) {
                            final folder = folders[index];
                            return Material(
                              color: surfaceColor,
                              borderRadius: BorderRadius.circular(18),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(18),
                                onTap: () => _navigate(folder.path),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.folder_outlined,
                                        color: accentColor,
                                        size: 26,
                                      ),
                                      const Spacer(),
                                      Text(
                                        folder.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        app.local ? '已下载 · 点击听歌' : '歌手 / 专辑目录',
                                        style: const TextStyle(
                                          color: mutedColor,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    SliverList.builder(
                      itemCount: tracks.length,
                      itemBuilder: (context, index) {
                        final entry = tracks[index];
                        final downloaded =
                            app.library?.localPath(entry) != null;
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
                                  ? '${downloaded ? '已下载 · ' : ''}原创合成试听 · WAV'
                                  : '${downloaded ? '已下载 · ' : ''}${entry.extension.toUpperCase()} · ${_size(entry.size)}',
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
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: app.isFavorite(entry)
                                            ? '取消喜欢'
                                            : '喜欢这首歌',
                                        onPressed: () =>
                                            app.toggleFavorite(entry),
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
                                      if (app.transfers != null)
                                        PopupMenuButton<String>(
                                          tooltip: '歌曲操作',
                                          onSelected: (action) =>
                                              _trackAction(entry, action),
                                          itemBuilder: (_) => [
                                            if (!downloaded)
                                              const PopupMenuItem(
                                                value: 'download',
                                                child: Text('下载到本地'),
                                              ),
                                            if (!entry.demo && app.connected)
                                              const PopupMenuItem(
                                                value: 'online',
                                                child: Text('在线播放'),
                                              ),
                                            if (downloaded)
                                              const PopupMenuItem(
                                                value: 'remove',
                                                child: Text('移除本地下载'),
                                              ),
                                          ],
                                        ),
                                    ],
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
                    if (!app.local && app.nextStart != null)
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
                            app.local
                                ? '已下载 ${app.library?.entries.length ?? 0} 首 · ${formatBytes(app.library?.totalBytes ?? 0)} · 保存在 App 内'
                                : app.demo
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
                      onPressed: () {
                        setState(() => _onlyFavorites = false);
                        _search.clear();
                        unawaited(app.openLibrary());
                      },
                      icon: const Icon(Icons.library_music_outlined, size: 21),
                      label: const Text('音乐库'),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        app.showLocal();
                        _search.clear();
                        setState(() => _onlyFavorites = false);
                      },
                      icon: const Icon(Icons.offline_pin_outlined, size: 21),
                      label: const Text('本地'),
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
