import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/baidu_client.dart';
import '../models/drive_entry.dart';
import '../models/music_directory.dart';

Future<void> manageSong(
  BuildContext context,
  AppController app,
  DriveEntry entry, {
  required bool deleting,
}) async {
  if (!app.canManage(entry)) return;
  String? target;
  if (!deleting) {
    target = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => MoveDestinationScreen(controller: app, entry: entry),
      ),
    );
    if (target == null || !context.mounted) return;
  }
  if (!context.mounted) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: Text(deleting ? '删除网盘歌曲？' : '移动这首歌曲？'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(entry.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          SelectableText(entry.path),
          const SizedBox(height: 12),
          Text(
            deleting
                ? '将请求百度删除这个音频文件。已下载的本地副本会保留；同目录歌词和封面不会删除。'
                : '移动到：\n$target\n\n同名文件不会覆盖。同目录的歌词和共享封面不会移动；已缓存的资料会保留。',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: deleting
              ? FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFB94845),
                  foregroundColor: Colors.white,
                )
              : null,
          child: Text(deleting ? '删除网盘文件' : '确认移动'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    if (deleting) {
      await app.deleteSong(entry);
    } else {
      await app.moveSong(entry, target!);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            app.operationNotice ??
                (deleting ? '网盘音频已删除，本地下载已保留' : '歌曲已移动到 $target'),
          ),
        ),
      );
    }
  } catch (failure) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failure is DriveException
                ? failure.message
                : '操作结果无法确认，请刷新源目录和目标目录核实后再操作',
          ),
        ),
      );
    }
  }
}

class MoveDestinationScreen extends StatefulWidget {
  const MoveDestinationScreen({
    super.key,
    required this.controller,
    required this.entry,
  });
  final AppController controller;
  final DriveEntry entry;
  @override
  State<MoveDestinationScreen> createState() => _MoveDestinationScreenState();
}

class _MoveDestinationScreenState extends State<MoveDestinationScreen> {
  late String path = widget.controller.musicRoot!;
  List<DriveEntry> folders = [];
  int? next;
  bool busy = false;
  String? error;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    _load(path);
  }

  Future<void> _load(String destination, {bool more = false}) async {
    final token = ++generation;
    setState(() {
      busy = true;
      error = null;
      if (!more) {
        path = destination;
        folders = [];
        next = null;
      }
    });
    try {
      final page = await widget.controller.listMusicFolders(
        destination,
        start: more ? next! : 0,
      );
      if (!mounted || token != generation) return;
      setState(() {
        folders = [...folders, ...page.entries];
        next = page.nextStart;
      });
    } catch (failure) {
      if (mounted && token == generation) {
        setState(
          () => error = failure is DriveException
              ? failure.message
              : '目录加载失败，请重试',
        );
      }
    } finally {
      if (mounted && token == generation) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('移动到其他目录')),
    body: Column(
      children: [
        ListTile(
          title: Text(path),
          subtitle: Text('来源：${widget.entry.parent}'),
          trailing: path == widget.controller.musicRoot
              ? null
              : IconButton(
                  tooltip: '返回上级目录',
                  onPressed: busy
                      ? null
                      : () => _load(path.substring(0, path.lastIndexOf('/'))),
                  icon: const Icon(Icons.arrow_upward),
                ),
        ),
        if (error != null)
          Padding(padding: const EdgeInsets.all(16), child: Text(error!)),
        Expanded(
          child: ListView(
            children: [
              for (final folder in folders)
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(folder.name),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: busy ? null : () => _load(folder.path),
                ),
              if (busy)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                ),
              if (!busy && next != null)
                TextButton(
                  onPressed: () => _load(path, more: true),
                  child: const Text('加载更多目录'),
                ),
              if (!busy && error != null)
                TextButton(
                  onPressed: () => _load(path),
                  child: const Text('重试'),
                ),
              if (!busy && error == null && folders.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('没有子目录，可选择当前目录'),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed:
                    busy ||
                        error != null ||
                        path == widget.entry.parent ||
                        !MusicDirectory.contains(
                          widget.controller.musicRoot,
                          path,
                        )
                    ? null
                    : () => Navigator.pop(context, path),
                icon: const Icon(Icons.drive_file_move_outlined),
                label: const Text('移动到此目录'),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
