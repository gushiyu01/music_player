云间的首个个人使用 MVP，使用 Flutter 开发。手机直接调用百度网盘接口并读取音频，无需部署后台服务。

- Android 8.0 及以上；安装附件 `cloud-music-android.apk`。
- 目录浏览、分页、文件名搜索、收藏、队列、进度、随机和循环播放。
- 后台播放、系统媒体控制、上一首/下一首及播放位置恢复。
- 安装后先点“晨光”或“潮汐”体验原创合成音频；连接真实网盘时，在“连接”中填写自己的 AppKey 和 SecretKey，并在百度官方页面完成授权。
- 没有内置百度凭据；个人配置与 token 仅保存于设备安全存储。只导入 access token 时无法自动刷新。

静态分析、自动测试、Android release 构建与 Android 15 模拟器演示播放检查通过。iOS 无签名编译产物保留在 Actions；安装到 iPhone 仍需要 Apple 开发者签名。

实际可访问的网盘目录、音频格式和下载速度需要使用者在自己的账号和设备上确认。本次没有进行真实百度账号联调。

安装和连接说明：https://github.com/gushiyu01/music_player#readme
