# MVP 验证记录

## v0.2.1 指定音乐目录

日期：2026-10-29（Asia/Shanghai）。本地 Dart 格式、Flutter 静态分析与 46 项自动测试通过。

新增覆盖：未配置目录及旧 `/` 配置启动时不请求文件列表；手动指定目录与路径规范化；仅加载当前目录的直接子项及分页；根目录返回边界；阻止父目录、同名前缀目录与 `..` 越界；指定目录失败时不回退 `/`；切换入口后忽略旧响应；旧远程队列过滤；上传及旧任务重试范围检查。界面测试验证指定目录输入、错误提示、取消后保留配置，以及分类/歌手卡片。

本地还渲染并检查了目录设置页、输入错误提示和分类列表，使用模拟 API。真实百度账号、目录权限与读写速度仍未实测。

最终源码：`36ff1bdb535a4cd70f8ceb5915830bea5de34bad`。Android versionCode：10。

完整构建：[GitHub Actions 40800148524](https://github.com/gushiyu01/music_player/actions/runs/40800148524)。四项任务全部成功：分析与 46 项测试、个人签名的 Android release APK、Android 15 模拟器检查、iOS release 无签名编译。设备检查包含播放、返回桌面继续播放、系统暂停/恢复、队列、下载后结束进程并禁用网络，再从本地文件播放；已检查截图与系统媒体会话证据。

[v0.2.1 发布](https://github.com/gushiyu01/music_player/releases/tag/v0.2.1)由[发布任务 40801431881](https://github.com/gushiyu01/music_player/actions/runs/40801431881)从该成功构建下载并校验同一 APK 后生成，安装包大小为 58,751,075 字节。

## v0.2.0 本次扩展

日期：2026-10-29（Asia/Shanghai）。本地 Dart 格式、Flutter 静态分析与 31 项自动测试通过。

新增覆盖：按“五月天 / 许嵩 / 周杰伦”等目录进入歌曲、记住音乐库入口、持久下载重启恢复、截断和孤立文件清理、路径隔离、下载去重/取消/重试、分片上传顺序与 MD5、上传冲突保护、取消后不提交文件、目录创建。

最终源码：`3fcef6b8b2a5fcf2a350ec2697b17dc930ff64e1`。Android versionCode：9。

完整构建：[GitHub Actions 40738332972](https://github.com/gushiyu01/music_player/actions/runs/40738332972)。四项任务全部成功：分析与 31 项测试、固定个人签名的 Android release APK、Android 15 模拟器检查、iOS release 无签名编译。

设备检查实际完成：安装并启动 release APK，播放原创试听音频，返回桌面继续播放，系统暂停/恢复，查看完整播放页和队列，从播放页下载音频，结束 App 进程并关闭 Wi-Fi/移动网络，重启后从“本地”进入已下载目录并播放。播放器确认选择的是 `AudioSource.file`，系统媒体会话处于 PLAYING。设备产物含六张截图和对应日志。

上传使用分段磁盘读取；检查依赖源码时发现原 file_selector_android 会读取全部文件字节，最终版本已替换为 file_picker 的磁盘文件接口。上传协议的自动测试覆盖分片校验、冲突与取消；没有连接用户真实百度账号，也没有执行真实百度上传。实际目录读写权限、配额和速度仍需在用户账号下联调。

下载位于 App 私有持久目录，卸载/清除数据会移除。传输需要保持 App 运行，进程结束后的不完整文件会清理，不提供跨进程续传。iOS 完成编译，尚无签名与真机测试。

## v0.1.0 基线

日期：2026-10-29（Asia/Shanghai）。应用版本：0.1.0，Android versionCode：6。

被验证的源码提交：`fc5ee2de66f7f0c21cbcc8e44a6edbb3ca27a462`。

完整构建：[GitHub Actions 40724320189](https://github.com/gushiyu01/music_player/actions/runs/40724320189)。四个任务均成功。

| 检查 | 结果 |
| --- | --- |
| Dart 格式与 Flutter 静态分析 | 通过，无分析问题 |
| 自动测试 | 15 项通过 |
| Android release APK | 构建成功，使用仓库的固定个人签名 |
| Android 15 / API 35，Pixel 6 x86_64 模拟器 | APK 安装、启动成功 |
| 原创试听音频 | 播放成功，系统媒体会话进入 PLAYING |
| 返回桌面 | 继续处于 PLAYING |
| 系统暂停与恢复 | 分别进入 PAUSED 和 PLAYING |
| 完整播放页、播放队列 | 页面打开并保存截图 |
| iOS release | 无签名 Runner.app 编译成功 |

自动测试覆盖临时 OAuth 故障保留授权、并发刷新合并、退出及授权取消竞态、目录分页与错误、下载域名/重定向/Range、失效链接恢复，以及界面搜索、收藏和队列。

设备证据在该次 Actions 的 `android-device-evidence` 产物，包括四张截图、前台/后台/系统控制媒体会话记录，以及 logcat。测试先验证恢复播放，再暂停后检查队列，避免持续更新的进度条影响 UIAutomator 的空闲状态检测。

## 尚未验证的范围

- 没有连接用户真实百度账号。设备码授权、真实目录权限、真实音乐下载和拖动性能需要在用户账号下联调；模拟 HTTP 测试不能替代这一环节。
- 模拟器验证使用打包的原创试听音频，没有实测国内网络、手机厂商后台限制、实际蓝牙耳机或长时间连续播放。
- iOS 完成编译，没有进行真机播放验证。无签名 App 不能直接安装到 iPhone，仍需要 Apple 签名。

应用采用 Flutter 手机直连架构，不需要 Cloudflare 或其他项目后台；参考项目审查与实现的当前范围见 README。
