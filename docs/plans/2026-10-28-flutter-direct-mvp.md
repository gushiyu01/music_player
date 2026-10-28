# Flutter 百度网盘直连 MVP Implementation Plan

**Goal:** 提供个人使用的 Android APK，以手机直接访问自己的百度网盘，保留 iOS 工程与编译验证。

**Architecture:** Flutter 界面调用设备码 OAuth 和百度网盘开放 API，just_audio 与 audio_service 负责直连播放及系统媒体控制。没有自建后台、Cloudflare、代理服务器或服务端数据库。安装后由用户输入自己的 AppKey/SecretKey，或导入 access token；凭据仅保存于设备安全存储，构建不需要百度密钥。

**Tech Stack:** Flutter、Dart、http、flutter_secure_storage、just_audio、audio_service、audio_session、shared_preferences、url_launcher、GitHub Actions。

此计划取代此前原生 Kotlin 与 Cloudflare 候选设计。用户已授权直接开发并用 GitHub Actions 构建，按当前会话执行。

## 1. 初始化与 CI

- 初始化 `gushiyu01/music_player` 仓库，保留参考审查文档。
- 创建 Flutter Android/iOS 工程，锁定 SDK 和 pubspec.lock。
- `.github/workflows/build.yml` 执行格式、分析、测试、Android APK 构建、iOS 无签名编译。
- 安卓个人签名文件放 GitHub Actions Secrets，保证后续 APK 可覆盖升级；不提交签名密钥。

## 2. 直连 API 与授权

- `lib/data/baidu_client.dart`：设备码申请/轮询、token 刷新、目录分页、文件元信息和 dlink。
- `lib/data/session_store.dart`：安全存储应用配置和 token；临时错误保留授权、刷新合并、退出清理。
- `lib/models/drive_entry.dart`：目录/歌曲模型，稳定文件 ID，未知标签回退文件名。
- 只读目录浏览，不实现远程删除/修改；分页失败保留已载入数据，路径/权限错误明确报告，不做缺失同步。
- 对 dlink 和重定向逐跳校验 HTTPS 百度域名，下载仅发送所需 UA 和百度 access token，不向任意域名发送凭据。

## 3. 播放与界面

- `lib/playback/music_handler.dart`：按队列逐曲获取新 dlink，自动下一曲、上一曲、进度、循环、随机、暂停恢复、有限重试。
- `lib/app_controller.dart`：目录状态、当前目录搜索、收藏、最近目录、队列与本地播放位置。
- `lib/ui/`：深色音乐库、文件夹导航、搜索、迷你播放器、完整播放页、队列和连接设置。
- 提供原创合成音频演示模式，安装后可先测试基本播放，不依赖账号。
- Android 配置前台媒体服务，iOS 配置后台音频；只为播放器的本地 HTTP 转接允许 localhost 明文，不允许远程 HTTP。

## 4. 验证与交付

- API 测试覆盖 OAuth 暂时失败保留 token、并发刷新合并、授权替换、错误分类、目录翻页与 dlink 域名/Range/重定向。
- Widget 测试覆盖演示歌曲、目录过滤、未连接提示和设置入口。
- CI 必须分析/测试成功并生成 APK；检查实际运行日志和产物。
- 最好使用 Android 模拟器安装并启动 APK，检查演示播放及后台状态。
- README 说明安装、个人百度应用配置、直连机制、权限限制、iOS 签名要求和实测边界。
- 最终通过企微发送仓库、构建和 APK 结果，明确尚未执行真实百度账号联调。
