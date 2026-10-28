# 百度网盘音乐播放器：参考项目审查

审查日期：2026-10-28。使用范围：仅自己使用，连接自己的一个百度网盘账号。

参考目录：`D:/work/project/vibe-coding/zcode/mobile/cloudflare`。本文中的源文件链接均指向本次审查时的参考代码，后续修改可能使行号变化。

## 结论

可以复用百度网盘授权、文件列表、文件索引和音频流代理的部分实现。现有项目是 Vue 文件管理器加 Cloudflare 后端，不能直接作为完整的安卓音乐播放器交付。接入前应修复下列六个已经通过模拟依赖复现的问题。

本文记录参考代码审查阶段的类型检查和隔离复现，没有修改参考项目、部署或连接真实百度账号。后续已按用户要求在当前仓库实现 Flutter 手机直连 MVP；不再依赖参考项目的 Cloudflare 后端。应用构建与运行结果以仓库 README 及 Actions 为准。

## 已复现的问题

### R2 · P1：临时 OAuth 故障清空授权记录

位置：[token-object.ts](D:/work/project/vibe-coding/zcode/mobile/cloudflare/worker/src/baidu/token-object.ts:223)。

`doRefresh()` 对任何包含 `error` 的响应都删除已保存的 token。模拟 OAuth 返回 HTTP 503 和 `server_error` 后，原有授权记录被删除，用户必须重新授权。源码注释中“刷新失败就永久作废”的断言不能作为所有服务端错误都应清空凭据的依据。

修复：区分明确的凭据失效与可恢复的服务故障；后者保留凭据并返回临时错误，采用有上限的退避重试。具体哪些百度错误表示最终失效，需要结合正式接口规范及实测确定。

### R4 · P1：分批同步重复全量扫描，目录变化会漏歌

位置：[sync-service.ts](D:/work/project/vibe-coding/zcode/mobile/cloudflare/worker/src/services/sync-service.ts:60)。

每一轮都执行 `mkdir()` 和整棵目录树扫描，只把其中 30 条写入数据库，随后通过数组 offset 续传。复现条件：61 首歌，第一轮写入前 30 首；删除网盘中排序第一首；第二轮重新扫描后仍从 offset 30 开始，最终 `/music/031.mp3` 没有入库，但同步报告完成。

修复：使用持久化同步任务，保存待扫描目录、分页进度和本轮已发现的文件集合；批次间不能把重新扫描得到的可变数组当作稳定快照。完整扫描成功之后才执行缺失核对。同步播放器目录时也应取消自动建目录行为，避免只读同步隐含修改网盘。

### R6 · P1：目录错误被当作不存在，整棵子树误标缺失

位置：[errors.ts](D:/work/project/vibe-coding/zcode/mobile/cloudflare/worker/src/support/errors.ts:43)、[client.ts](D:/work/project/vibe-coding/zcode/mobile/cloudflare/worker/src/baidu/client.ts:197)、[sync-service.ts](D:/work/project/vibe-coding/zcode/mobile/cloudflare/worker/src/services/sync-service.ts:108)。

`isNotFound` 同时包含 `-9` 和 `-7`；其中 `-7` 在参考代码中定义为 `BAD_PATH`，提示“文件或目录名非法，或无权访问”。递归扫描因此跳过该子目录，最终仍进行完整集合核对。模拟子目录返回 `-7`，其下已索引的 `/music/private/existing.mp3` 被标记为 missing，同步报告完成。

这会错误影响本地音乐库状态，不会删除百度网盘中的原始音乐。本次复现确认了代码分支的行为，没有验证真实百度账号在各种权限情形下返回什么错误码。

修复：将路径/权限异常与确定不存在分开；扫描任何子树失败时，整轮不得核对该子树的缺失状态。

### R1 · P1：播放失败统一转换为文件不存在

位置：[client.ts](D:/work/project/vibe-coding/zcode/mobile/cloudflare/worker/src/baidu/client.ts:519)、[http.ts](D:/work/project/vibe-coding/zcode/mobile/cloudflare/worker/src/support/http.ts:33)。

实际执行 `openDlink()`，模拟上游分别返回 403、416、429、500，最终 API 错误映射均为 HTTP 404 / `NOT_FOUND`。416 的 `Content-Range` 也被丢弃。安卓端将无法正确区分授权/下载链接问题、进度越界、限流和服务故障。当前下载路径也没有与元数据请求等价的授权恢复逻辑。

修复：保留上述错误类别及 Range 响应语义；需要时重新获取 dlink，必要时刷新 token 后仅重试有限次数。不能在流已经发送一半时无条件从头重放，也不能把所有 403 都解释为 token 过期。

### R3 · P2：强制刷新排队后仍会重复请求 OAuth

位置：[token-object.ts](D:/work/project/vibe-coding/zcode/mobile/cloudflare/worker/src/baidu/token-object.ts:191)。

普通过期刷新在排队后会重新读取并复用最新 token；但 `force=true` 会绕过这个判断。五个并发强制刷新请求产生五次 OAuth 请求。这里确认的是重复刷新，没有证明百度会因此永久废弃授权。

修复：刷新请求携带刚被拒绝的 token 或版本，若队列中已有请求完成刷新，就复用新版本；或合并同一次刷新中的并发请求。

### R5 · P2：修改密码后旧登录会话继续有效

位置：[api.ts](D:/work/project/vibe-coding/zcode/mobile/cloudflare/worker/src/routes/api.ts:149)、[jwt.ts](D:/work/project/vibe-coding/zcode/mobile/cloudflare/worker/src/auth/jwt.ts:53)。

实际执行修改密码路由返回 204，之前签发的 Cookie 随后访问 `/api/auth/me` 仍返回 200。默认配置的会话有效期为 168 小时。若曾有会话泄露，修改密码无法立即使它失效。

修复：单用户场景可增加会话版本，在修改密码时递增，并在每次鉴权时核对；也可采用支持撤销的服务端会话。

## 可以保留的实现及已验证的控制

- 单管理员、单百度 token Durable Object 符合个人自用的范围，不需要为了这个需求引入多租户系统。
- 流式代理在受信任的 302 跳转后保留 `Range` 和 `User-Agent: pan.baidu.com`，并正确保留上游 206、Content-Range 和响应体。
- 模拟重定向到 `127.0.0.1` 时，在访问目标之前被域名白名单拦截。这只是一个已通过的控制案例，不代表完整 SSRF 审计结论。

## 做安卓音乐播放器还缺什么

- 原生后台播放、锁屏/通知控制、耳机控制、音频焦点和来电恢复策略。现有网页 `<audio>` 不能充当这些功能已经实现的证据：[MediaViewer.vue](D:/work/project/vibe-coding/zcode/mobile/cloudflare/frontend/src/components/MediaViewer.vue:323)。
- 音乐专用元数据和状态：时长、歌手、专辑、封面、曲目序号、播放队列及播放位置。当前模型主要是通用文件字段：[schema.sql](D:/work/project/vibe-coding/zcode/mobile/cloudflare/worker/src/db/schema.sql:20)。首版可以先以文件名展示，播放时逐步补充可获取的元数据。
- Android API 请求与播放器媒体请求必须共用一致的鉴权。参考项目依赖 `picman_token` Cookie；播放器不能假设自动继承浏览器或其他 HTTP 客户端的登录态。
- 默认扫描目录是 `/apps/picman`。修改配置并不等于应用自动获得其他目录权限；真实音乐目录是否可列出、是否可获取 dlink，需要在用户自己的授权下验证。
- 新项目应新建 Cloudflare 资源配置，保留适用的 MIT 许可声明；不能直接沿用参考配置中的 D1/KV 资源标识。

## 已执行的检查与边界

| 检查 | 结果 | 能说明什么 |
| --- | --- | --- |
| Worker `npm run typecheck` | 通过 | 当前参考后端类型检查成功 |
| Frontend `npm run typecheck` | 通过 | 当前参考网页前端类型检查成功 |
| 隔离复现脚本 | 六个缺陷确认、两个控制确认、零个探针执行失败 | 在模拟上游与存储条件下复现实际源代码行为 |
| 真实百度授权及目录访问 | 未执行 | 读取范围、速率、错误码和链接寿命待实测 |
| 手机播放及国内实际网络 | 未执行 | 起播、拖动、长时间播放、后台保活待实测 |
| Android 构建 | 未执行 | 常见安装路径与当前 PATH 未发现 SDK/adb/Gradle；Java 17 已存在 |

复现脚本：[review-reference.mjs](D:/work/project/vibe-coding/codex/music_player/tools/review-reference.mjs)。在当前工作区运行：

```powershell
node tools/review-reference.mjs
```

也可用第一个参数指定其他参考目录。脚本需要该参考项目已经安装 TypeScript 依赖；所有 HTTP 和 token 存储均被替换为模拟实现，不读取真实密钥，不请求远程服务。

## 下一步建议

建议先修复授权保留、同步完整性和播放错误语义，再用一个真实音乐目录验证列表、dlink、起播与拖动，最后完成安卓播放链路。候选首版设计见 [设计草案](D:/work/project/vibe-coding/codex/music_player/docs/plans/2026-10-28-personal-netdisk-music-design.md)。
