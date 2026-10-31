import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../main.dart';

class CacheScreen extends StatefulWidget {
  const CacheScreen({super.key, required this.controller});
  final AppController controller;
  @override
  State<CacheScreen> createState() => _CacheScreenState();
}

class _CacheScreenState extends State<CacheScreen> {
  bool busy = false;
  String? notice;

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除歌曲缓存？'),
        content: const Text('将停止当前播放并清除自动缓存。手动下载的歌曲、歌词和封面会保留；之后在线播放会重新缓存。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('停止播放并清除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      busy = true;
      notice = null;
    });
    try {
      await widget.controller.clearPlaybackCache();
      if (mounted) setState(() => notice = '歌曲缓存已清除，手动下载已保留');
    } catch (_) {
      if (mounted) setState(() => notice = '部分缓存未能清除，请稍后重试');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _size(int bytes) =>
      bytes == 0 ? '0 MB' : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('歌曲缓存')),
    body: AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final cache = widget.controller.cache;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.storage_outlined, size: 44, color: accentColor),
            const SizedBox(height: 24),
            Text(
              _size(cache?.totalBytes ?? 0),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w600),
            ),
            Text(
              '已缓存 ${cache?.entries.length ?? 0} 首 · 上限 1 GB',
              textAlign: TextAlign.center,
              style: const TextStyle(color: mutedColor),
            ),
            const SizedBox(height: 24),
            const Text(
              '在线播放会自动缓存，完整保存后下次优先从本地播放。缓存歌曲也能在“本地”找到。超过上限时自动清理较早使用的缓存。',
              style: TextStyle(height: 1.8),
            ),
            const SizedBox(height: 12),
            const Text(
              '自动缓存使用 App 私有存储，可随时清除。手动下载的歌曲会长期保留，不受缓存清理影响。',
              style: TextStyle(color: mutedColor, height: 1.8),
            ),
            if ((cache?.activeCount ?? 0) > 0)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Text('正在缓存当前歌曲…', style: TextStyle(color: accentColor)),
              ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed:
                  busy ||
                      cache == null ||
                      (cache.entries.isEmpty && cache.activeCount == 0)
                  ? null
                  : _clear,
              icon: const Icon(Icons.delete_sweep_outlined),
              label: Text(busy ? '正在清除…' : '清除歌曲缓存'),
            ),
            if (notice != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(notice!),
              ),
          ],
        );
      },
    ),
  );
}
