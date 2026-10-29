# 歌词、封面与歌曲管理 Implementation Plan

**Goal:** 支持歌词与真实封面，并允许每首网盘歌曲移动和删除。

**Architecture:** 保留 Flutter 客户端直连。歌曲资料优先缓存、同目录文件及 MP3/FLAC 内嵌标签，缺失时用户主动在线搜索并选择；第三方搜索使用独立 HTTP 客户端。移动、删除调用百度官方同步 filemanager，路径范围仍是指定音乐目录。

**Tech Stack:** Flutter、Dart、http、audio_service、百度网盘 filemanager、LRCLIB、MusicBrainz / Cover Art Archive。

## 实施

1. `lib/data/baidu_file_actions.dart` 实现单曲移动和删除，检查逐文件 errno，同名目标拒绝覆盖，无法确认结果时提示刷新后核实。控制器阻止演示歌曲、目录、范围外路径和并发重复操作。目录选择器按需加载一层并支持分页；删除对话框列出歌曲和完整路径，确认后才请求。
2. `lib/models/song_details.dart`、`lib/data/audio_tags.dart` 支持 LRC 时间、offset、纯文本以及有限大小的 MP3 ID3v2.3/2.4 和 FLAC 标签。`lib/data/song_details_repository.dart` 从同父目录匹配同名 LRC/图片或 cover/folder/front 图片；头部解析最多读取 2 MB，歌词 256 KB，图片 5 MB；不扫描子目录。结果缓存供重启和离线使用。
3. `lib/data/online_catalog.dart` 提供手动歌词/封面候选搜索，选择后本机缓存；不写回音乐文件，不把百度凭据传给第三方。`lib/ui/song_details_screen.dart` 展示时间歌词、当前行和跳转，提供资料刷新、搜索及手机文件导入。
4. 播放列表、迷你播放器、完整播放页和媒体通知展示缓存封面。移动成功更新队列、本地副本目录及缓存；删除只删除选中网盘音频，保留本地下载并阻止旧下载任务重新访问已删除路径。共享目录封面及歌词文件不随音频删除。
5. 先以模拟接口验证请求协议、错误与范围、取消删除、移动目标选择、歌词解析、畸形标签、有界读取和缓存重启。运行格式、analyze 和完整测试，再由 GitHub Actions 构建 APK、设备检查和 iOS 无签名编译；发布验证过的版本，最后发一次企微汇总。

## 验证边界

不访问或修改用户真实网盘。中文歌的第三方命中率和真实读写权限需要用户设备联调；不保证每首歌自动找到对应版本。内嵌标签只覆盖前 2 MB 内的常用 MP3/FLAC 标签，其他格式可使用同目录文件、手机导入或在线匹配。

## 接口依据

- https://github.com/baidu-netdisk/baidu-drive-sdk-go/blob/main/baidudriver/api/file_manager.go
- https://lrclib.net/docs
- https://musicbrainz.org/doc/MusicBrainz_API
- https://musicbrainz.org/doc/Cover_Art_Archive/API
- https://id3.org/id3v2.3.0
- https://id3.org/id3v2.4.0-structure
- https://www.xiph.org/flac/format.html
