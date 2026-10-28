import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_controller.dart';
import '../data/baidu_client.dart';
import '../data/session_store.dart';
import '../main.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key, required this.controller});
  final AppController controller;
  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final _key = TextEditingController();
  final _secret = TextEditingController();
  final _token = TextEditingController();
  DeviceGrant? _grant;
  Timer? _poll;
  DateTime? _deadline;
  int _interval = 5;
  bool _busy = false;
  bool _polling = false;
  bool _hideSecret = true;
  String? _message;

  @override
  void initState() {
    super.initState();
    _key.text = widget.controller.client.session.appKey;
    _secret.text = widget.controller.client.session.secretKey;
  }

  @override
  void dispose() {
    _poll?.cancel();
    widget.controller.client.cancelPendingAuthorization();
    _key.dispose();
    _secret.dispose();
    _token.dispose();
    super.dispose();
  }

  void _notice(String message) {
    if (mounted) setState(() => _message = message);
  }

  void _schedulePoll() {
    _poll?.cancel();
    _poll = Timer(Duration(seconds: _interval), () => unawaited(_check()));
  }

  Future<void> _authorize() async {
    if (_key.text.trim().isEmpty || _secret.text.trim().isEmpty) {
      _notice('请填写自己的 AppKey 和 SecretKey');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final grant = await widget.controller.client.requestDevice(
        _key.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _grant = grant;
        _deadline = DateTime.now().add(Duration(seconds: grant.expiresIn));
        _interval = grant.interval.clamp(5, 60);
      });
      _schedulePoll();
      await _openAuthorization();
    } catch (error) {
      _notice(error is DriveException ? error.message : '无法打开授权，请检查网络');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openAuthorization() async {
    if (_grant == null) return;
    final opened = await launchUrl(
      _grant!.verificationUrl,
      mode: LaunchMode.externalApplication,
    );
    if (!opened) _notice('无法打开浏览器，请复制设备码后访问 openapi.baidu.com/device');
  }

  Future<void> _check() async {
    if (!mounted || _grant == null || _polling) return;
    if (DateTime.now().isAfter(_deadline!)) {
      _notice('设备码已过期，请重新发起授权');
      _poll?.cancel();
      return;
    }
    _polling = true;
    try {
      await widget.controller.client.completeDevice(
        _grant!,
        _key.text.trim(),
        _secret.text.trim(),
      );
      _poll?.cancel();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on DriveException catch (error) {
      if (error.code == 'slow_down') _interval += 5;
      if ([
        'authorization_pending',
        'slow_down',
        'network',
        'temporary',
        'server_error',
        'temporarily_unavailable',
      ].contains(error.code)) {
        if (error.code != 'authorization_pending') _notice(error.message);
        if (mounted) _schedulePoll();
      } else {
        _notice(error.message);
        _poll?.cancel();
      }
    } catch (_) {
      _notice('检查授权失败，请重新发起授权');
    } finally {
      _polling = false;
    }
  }

  Future<void> _import() async {
    final text = _token.text.trim();
    if (text.isEmpty || text.contains(RegExp(r'\s'))) {
      _notice('请粘贴完整的 access token，不是授权码或网页地址');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      // Validate with a separate client so a bad import cannot overwrite an
      // existing connection. Tokens never leave the official Baidu API host.
      final temporary = BaiduClient(
        _MemoryStore(DriveSession(accessToken: text)),
      );
      await temporary.initialize();
      try {
        await temporary.validateAuthorization();
      } finally {
        temporary.client.close();
      }
      await widget.controller.client.replaceSession(
        DriveSession(accessToken: text),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      _notice(error is DriveException ? error.message : '导入失败，请检查 token');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('连接百度网盘')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.cloud_outlined, size: 46, color: accentColor),
        const SizedBox(height: 18),
        const Text(
          '音乐在网盘，\n播放在你手中。',
          style: TextStyle(
            fontSize: 29,
            fontWeight: FontWeight.w700,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          '手机直连百度，不需要部署服务器。使用你自己的百度网盘开放平台应用，密钥和授权只存于本机安全存储。',
          style: TextStyle(color: mutedColor, height: 1.7),
        ),
        const SizedBox(height: 24),
        if (widget.controller.connected) ...[
          const Card(
            child: ListTile(
              leading: Icon(Icons.verified_user_outlined, color: accentColor),
              title: Text('已有网盘授权'),
              subtitle: Text('重新连接成功后会替换旧授权'),
            ),
          ),
          const SizedBox(height: 16),
        ],
        TextField(
          controller: _key,
          enabled: !_busy && _grant == null,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: '你的 AppKey',
            hintText: '百度网盘开放平台 → 应用信息',
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _secret,
          enabled: !_busy && _grant == null,
          obscureText: _hideSecret,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: '你的 SecretKey',
            suffixIcon: IconButton(
              tooltip: _hideSecret ? '显示密钥' : '隐藏密钥',
              onPressed: () => setState(() => _hideSecret = !_hideSecret),
              icon: Icon(
                _hideSecret
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _busy
              ? null
              : () {
                  if (_grant != null) {
                    _poll?.cancel();
                    setState(() => _grant = null);
                  } else {
                    unawaited(_authorize());
                  }
                },
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.link),
          label: Text(_grant == null ? '在百度页面授权' : '重新填写并授权'),
        ),
        if (_grant != null) ...[
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('在百度页面输入设备码', style: TextStyle(color: mutedColor)),
                  const SizedBox(height: 12),
                  SelectableText(
                    _grant!.userCode,
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 4,
                      color: accentColor,
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: _grant!.userCode),
                          );
                          _notice('设备码已复制');
                        },
                        icon: const Icon(Icons.copy, size: 17),
                        label: const Text('复制设备码'),
                      ),
                      TextButton(
                        onPressed: _openAuthorization,
                        child: const Text('打开百度页面'),
                      ),
                    ],
                  ),
                  const Text(
                    '完成后返回这里，应用会自动检查授权结果。',
                    style: TextStyle(color: mutedColor, height: 1.6),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (_message != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(
              _message!,
              style: const TextStyle(color: Color(0xFFFFCF9C), height: 1.6),
            ),
          ),
        const SizedBox(height: 16),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('已有 access token？'),
          subtitle: const Text(
            '高级方式 · 过期后需要重新导入',
            style: TextStyle(color: mutedColor),
          ),
          children: [
            const SizedBox(height: 10),
            TextField(
              controller: _token,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'access_token'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _busy ? null : _import,
              child: const Text('验证并导入'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const Text(
          '个人密钥仅适合自己使用的设备。请勿分发填好凭据的安装包。能访问的目录与下载速度由百度应用权限及账号权益决定。',
          style: TextStyle(fontSize: 12, color: mutedColor, height: 1.7),
        ),
        if (widget.controller.connected)
          TextButton.icon(
            onPressed: _busy
                ? null
                : () async {
                    _poll?.cancel();
                    await widget.controller.disconnect();
                    if (context.mounted) Navigator.of(context).pop(false);
                  },
            icon: const Icon(Icons.logout),
            label: const Text('断开连接并清除本机授权'),
          ),
      ],
    ),
  );
}

class _MemoryStore implements SessionStore {
  _MemoryStore(this.value);
  DriveSession value;
  @override
  Future<DriveSession> read() async => value;
  @override
  Future<void> write(DriveSession session) async {
    value = session;
  }

  @override
  Future<void> clear() async {
    value = const DriveSession();
  }
}
