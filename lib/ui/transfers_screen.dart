import 'package:flutter/material.dart';

import '../data/transfer_manager.dart';
import '../main.dart';

class TransfersScreen extends StatelessWidget {
  const TransfersScreen({super.key, required this.manager});
  final TransferManager manager;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('传输任务')),
    body: AnimatedBuilder(
      animation: manager,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            '传输时请保持 App 运行。中断后可重试；已下载的歌曲可断网播放。',
            style: TextStyle(color: mutedColor, height: 1.6),
          ),
          const SizedBox(height: 20),
          if (manager.tasks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 70),
              child: Center(child: Text('还没有传输任务')),
            ),
          for (final task in manager.tasks.reversed)
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          task.uploading
                              ? Icons.upload_outlined
                              : Icons.download_outlined,
                          color: accentColor,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            task.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (task.active)
                          IconButton(
                            tooltip: '取消传输',
                            onPressed: () => manager.cancel(task),
                            icon: const Icon(Icons.close),
                          )
                        else if (task.status != TransferStatus.done)
                          IconButton(
                            tooltip: '重试传输',
                            onPressed: () => manager.retry(task),
                            icon: const Icon(Icons.refresh),
                          )
                        else
                          const Icon(
                            Icons.check_circle_outline,
                            color: accentColor,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${task.uploading ? '上传到' : '来自'} ${task.destination}',
                      style: const TextStyle(color: mutedColor, fontSize: 12),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 10),
                    if (task.status == TransferStatus.running) ...[
                      LinearProgressIndicator(value: task.progress),
                      const SizedBox(height: 10),
                    ],
                    Text(
                      task.error ??
                          '${task.phase}${task.bytes > 0 ? ' · ${formatBytes(task.bytes)}' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        color: task.status == TransferStatus.failed
                            ? Colors.orange.shade200
                            : mutedColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

String formatBytes(int bytes) => bytes < 1024 * 1024
    ? '${(bytes / 1024).toStringAsFixed(0)} KB'
    : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
