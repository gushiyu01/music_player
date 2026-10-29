# 云间 · Personal Cloud Music

自己使用的 Flutter 音乐播放器，Android / iOS 共用一套界面与业务代码。
手机直接调用百度网盘官方接口、直接读取音频；无需 Cloudflare、自建后端、媒体中转或服务器数据库。

## 安装 Android

安装包放在 [Releases](https://github.com/gushiyu01/music_player/releases/latest)，下载 `cloud-music-android.apk` 即可安装。SHA256 校验文件与 APK 一起提供。

打开本仓库 **Actions → Build personal music player → 最近一次成功运行 → Artifacts → cloud-music-android**，下载并解压，安装 `cloud-music-android.apk`。

每次推送 main 或手动运行工作流都会重新构建。个人发布签名存放在 GitHub Actions Secrets，同一签名的后续版本可覆盖安装。首次安装需要允许当前下载工具安装应用。没有内置百度密钥，构建也不需要百度凭据。

安装后可直接点击 **晨光 · Dawn** 或 **潮汐 · Tide**，验证播放、队列、进度、通知与后台控制。这两段音频由项目脚本原创合成，属于演示内容，与真实网盘歌曲明确区分。

## 连接自己的百度网盘

1. 使用自己已有的百度网盘开放平台应用，或创建新应用，开通所需文件读取、下载及上传权限，取得自己的 **AppKey** 和 **SecretKey**。
2. 在 App 的 **连接** 页面填写这两项，点击 **在百度页面授权**。
3. 在打开的百度官方页面登录自己的账号，输入 App 显示的设备码并确认授权。
4. 返回 App，授权成功后先**指定音乐目录**，手动填写 `/音乐` 等完整网盘路径。未设置时不会读取文件列表；不能选择网盘根目录 `/`。
5. 首页展示指定目录下的分类或歌手文件夹，点开后才加载其中内容。返回上级止于音乐目录，底部“音乐库”回到该目录。搜索作用于当前目录已经加载的文件；大目录需要点击“加载更多文件”。

凭据由用户在安装后输入，使用 Android 系统保护的安全存储和 iOS Keychain 保存。源码、APK、GitHub Actions 均没有内置 AppKey、SecretKey 或 token。临时网络/百度故障会保留现有授权；刷新会合并并发请求，避免同一时刻重复刷新。断开连接会停止播放和传输，清除本机授权、队列与收藏，保留已下载歌曲供离线播放；不会撤销百度网站上已经授予的应用权限，需要时在百度侧自行撤销。

设备码模式与 token 刷新需要 SecretKey。因此这是一款**自己配置凭据、仅在自己设备上使用**的工具；不是把开发者共享 SecretKey 放入公开 APK 的登录方案。百度账号密码只在百度官方页面输入。

高级方式：在“已有 access token？”中导入具有网盘权限的 token。导入会先请求百度验证，不会用错误 token 覆盖已有连接。仅导入 access token 时无法自动刷新，失效后需要重新导入或使用设备码授权。

**可访问的目录与下载速度取决于百度应用权限、账号权益及实际网络。** 只读取用户指定的音乐目录及主动打开的子目录，不请求 `/`，不递归扫描网盘。若指定目录不存在或没有权限，显示错误供重试或更改目录，不会退回网盘根目录。某些音频格式也取决于设备解码支持，MP3/AAC/WAV 可先用作联调样本。

## MVP 功能

- 设备码授权、自动刷新、手动 token 导入与本机退出。
- 分类或歌手目录卡片、嵌套专辑目录、分页、当前已加载列表的文件名搜索。
- 首次连接先指定音乐目录，例如 `/音乐`，其下按“五月天”“许嵩”“周杰伦”或“摇滚”等真实子目录展示。
- 在线播放，以及 App 内持久下载、本地目录分类与断网播放；默认优先使用已下载文件，歌曲菜单可强制在线播放。
- 多选手机音乐上传到音乐目录范围内的当前文件夹、新建分类或歌手目录；分片 MD5 校验，同名文件不覆盖。
- 传输列表、进度、取消、失败重试；下载完成前不进入本地音乐库。
- 按当前列表建立播放队列，上一首/下一首、随机、单曲循环、列表循环。
- 音乐播放进度、迷你播放器和完整播放页。
- 原生后台音频服务，通知/锁屏/耳机媒体控制与耳机断开暂停。
- 时间歌词逐行高亮、点歌词跳转；读取同目录 LRC、常用 MP3 / FLAC 内嵌歌词与封面，支持手机导入及手动在线匹配，本机缓存后可离线查看。
- 单首网盘歌曲移动到音乐目录内的其他文件夹，或确认后删除网盘音频；目标同名文件不覆盖，本地下载与网盘删除分开处理。
- 本机收藏标记，重启后恢复上次队列与位置，用户点播放后继续。
- 原创音频离线演示。

歌手/分类仍按真实文件夹组织，不建立全盘标签索引，不修改音乐文件里的标签。收藏筛选作用于当前已加载目录。

## 按歌手听歌、下载和上传

建议在有访问权限的网盘目录中这样存放：

```text
/音乐/
  五月天/
    倔强.mp3
  许嵩/
    你自己的歌曲.flac
  周杰伦/
    专辑目录/
      你自己的歌曲.m4a
```

1. 连接后点 **指定音乐目录**，填写 `/音乐`。以后底部“音乐库”会回到这里；在 **目录设置 → 更改音乐目录** 可以切换入口。旧版没有设置目录或设置为 `/` 时，升级后也会先要求指定目录。
2. 点分类或歌手卡片，继续进入专辑子目录或直接点歌播放。只有主动打开目录才会加载其中内容。
3. 歌曲旁 **歌曲操作 → 下载到本地**，或在完整播放页点下载图标。底部 **本地** 按原父目录展示已下载歌曲，重启或断网后仍可播放。
4. **上传到此目录** 打开系统文件选择器，可多选音频。目标是按钮所在的当前网盘目录；在“传输任务”查看进度、取消或重试。单文件上限为本 MVP 设置的 2 GB，实际还受百度权限及配额限制。
5. **新建目录** 可以直接创建分类、歌手或专辑文件夹。上传同名文件时会提示更名，原文件保留。更改音乐目录后，范围外尚未完成的上传会取消，旧任务也不能重试到范围外；已下载的本地歌曲保留。

下载保存在 App 私有数据目录，不需要授予整个手机存储访问权限；卸载或清除 App 数据会移除这些文件。“移除本地下载”只删除手机上的副本。当前没有导出到系统 Downloads 的功能。

传输时请保持 App 运行。后台播放由原生音频服务支持；上传/下载暂不提供独立系统后台传输服务、跨进程断点续传。进程被结束后，完整下载仍保留，不完整文件会清理，可重新发起传输。

## 歌词与封面

在歌曲操作或完整播放页打开 **歌词与封面**。常用 MP3 ID3v2.3/2.4、FLAC 标签可提供歌名、歌手、专辑、歌词与封面；也可以在歌曲所在目录放置文件：

```text
/音乐/周杰伦/
  晴天.mp3
  晴天.lrc
  晴天.jpg
  cover.jpg
```

同名 `.lrc` 优先于内嵌歌词；封面优先使用内嵌图片，再寻找同名图片以及 `cover`、`folder`、`front` 的 JPG / JPEG / PNG / WebP。只检查歌曲当前父目录，最多 10 页、2000 项，不递归读取其他目录。音乐头部最多读取 2 MB，歌词最多 256 KB，图片最多 5 MB；大标签或其他音频格式可改用同目录文件或手机导入。

支持 UTF-8、UTF-16 与常见 GBK 歌词。LRC 显示当前行，点击一行可跳转；普通文本按全文展示。**导入歌词 / 导入封面** 从系统文件选择器读取，仅保存到本机，不上传、不修改网盘原文件。已缓存资料可在重启与断网后查看；卸载或清除数据会移除缓存。

**搜索歌词 / 搜索封面** 仅在手动搜索时把输入的歌名和歌手发送给 LRCLIB、MusicBrainz / Cover Art Archive，不发送百度凭据或音频。结果需要选择对应版本；中文歌曲命中率、版本与网络可用性不保证，找不到时可导入自己的文件。手机导入或已选在线资料优先保留；“重新读取网盘资料”不会覆盖这些选择。原创试听曲为器乐，附带的是时间轴说明，并非演唱歌词。

## 移动和删除歌曲

歌曲操作里的 **移动到其他目录** 从指定音乐目录开始逐层选择目标，确认后只移动这一首音频，不覆盖同名文件；成功后更新播放队列、本地下载目录和资料缓存。网盘旁边的 `.lrc` 或图片文件不会自动跟随移动，需要时在网盘中自行整理。

**删除网盘文件** 会再次显示歌名和完整路径，确认后删除该音频，保留手机已下载的副本以及同目录歌词和图片。删除后从当前网盘列表与播放队列移除；若需删除手机副本，另用 **移除本地下载**。本应用没有批量删除或目录删除功能。

移动和删除调用百度同步接口并检查逐文件结果。网络中断或响应无法确认时不自动重试破坏性操作，请先刷新目录核实。真实读写权限需要使用自己的百度账号验证。

## 为什么播放器里有 localhost

音频流由 Dart 直接向百度发送请求，用 `User-Agent: pan.baidu.com`、Range 和逐跳域名检查处理下载。`just_audio` 用**手机内部的 loopback HTTP 通道**把音频交给系统解码器。这不是远程代理服务器，音乐不流经本项目的任何服务器。远程下载只接受 HTTPS 百度域名，Android/iOS 只为本地回环通道开放明文访问。

每次开始/切歌都重新获取 dlink；403/410 会有限次重新取链接。416、限流、网络和服务端错误分别报告，不再统一伪装成“文件不存在”。不会把临时下载地址或 token 写进播放历史。

## 构建与验证

固定 Flutter **3.47.8**（revision `737ba8f885dc774b53b442759999a312c9461e4e`），Dart 3.13.7。用户本机不需要 Android SDK；APK 由 GitHub Actions 构建。

本地只检查 Dart/Flutter 代码时：

```sh
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

CI 执行静态分析、自动测试、Android release APK 构建、Android 模拟器播放与后台控制检查、下载后结束进程并禁用网络的本地文件播放与歌词缓存检查，以及 iOS release 无签名编译。设备截图和系统媒体会话日志保存在 `android-device-evidence` 产物。真实网盘授权、移动/删除以及真实上传/下载性能需要在使用者设备和账号下联调，模拟 API 测试不代表已经完成真实账号验证。

已完成的验证及实测边界见 [验证记录](docs/validation.md)。

发布新版本时，手动运行 **Publish verified Android APK**，填入完整成功的构建 Run ID 和新版本标签。发布任务校验构建状态、APK 校验和与签名，再把同一个已测试 APK 发布到 Releases。

可选仓库 Secrets（已经为当前个人仓库配置）：

| 名称 | 用途 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | 私人 JKS 的 Base64，alias 为 `personal` |
| `ANDROID_KEYSTORE_PASSWORD` | 私人 JKS 的 store/key 密码 |

若这些 Secrets 不存在（例如 fork 或 PR 构建），回退为测试签名；这种安装包与个人正式签名无法直接覆盖升级。不在工作流中注入百度凭据。

## iOS

`ios/` 包含原生工程与后台音频配置，Actions 编译无签名的 `Runner.app`。**无签名 App 不能直接安装到 iPhone**；真机安装、TestFlight 或 App Store 分发仍需要自己的 Apple 开发者签名与设备/分发配置。本仓库不包含 Apple 证书。

## 参考与许可

参考项目 PicMan 的网盘接口组织方式，其审查结果保留在 `docs/reference-review.md`。最终 MVP 按用户要求采用 Flutter 客户端直连，不依赖参考项目的 Cloudflare 部署。历史 Kotlin/Cloudflare 设计草案已被 `docs/plans/2026-10-28-flutter-direct-mvp.md` 取代。

接口依据：

- [百度网盘 SDK 的设备码接口](https://github.com/baidu-netdisk/baidu-drive-sdk-go/blob/main/baidudriver/api/auth_device_code.go)
- [百度网盘 SDK 的 token 交换接口](https://github.com/baidu-netdisk/baidu-drive-sdk-go/blob/main/baidudriver/api/auth_device_token.go)
- [百度网盘 SDK 的预上传接口](https://github.com/baidu-netdisk/baidu-drive-sdk-go/blob/main/baidudriver/api/upload_precreate.go)
- [百度网盘 SDK 的分片上传接口](https://github.com/baidu-netdisk/baidu-drive-sdk-go/blob/main/baidudriver/api/upload_slice.go)
- [百度网盘 SDK 的移动/删除接口](https://github.com/baidu-netdisk/baidu-drive-sdk-go/blob/main/baidudriver/api/file_manager.go)
- [LRCLIB 歌词接口](https://lrclib.net/docs)
- [MusicBrainz API](https://musicbrainz.org/doc/MusicBrainz_API)
- [Cover Art Archive API](https://musicbrainz.org/doc/Cover_Art_Archive/API)
- [百度 OAuth 接入文档](https://openauth.baidu.com/doc/doc.html)
- [just_audio](https://pub.dev/packages/just_audio)
- [audio_service 的 Android/iOS 配置](https://pub.dev/packages/audio_service)

本项目代码与原创合成试听音频使用 MIT 许可，第三方包遵循各自许可。
