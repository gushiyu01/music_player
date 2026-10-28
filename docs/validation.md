# MVP 验证记录

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
