import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/ws_client.dart';
import '../../../core/storage/server_store.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../models/json_utils.dart';
import '../providers/container_providers.dart';

/// 弹出「拉取镜像」面板。返回 true 表示拉取成功（调用方应刷新列表）。
Future<bool> showImagePullSheet(BuildContext context) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => const _ImagePullSheet(),
  );
  return result ?? false;
}

/// 镜像拉取面板。
///
/// 优先使用 `GET /api/ws/container/image/pull`（连接后发送
/// `{name, auth, username, password}`）以获得逐层进度；
/// 未配置面板账号密码（WS 无法认证）时自动回退到
/// `POST /api/container/image` 的阻塞式拉取。
class _ImagePullSheet extends ConsumerStatefulWidget {
  const _ImagePullSheet();

  @override
  ConsumerState<_ImagePullSheet> createState() => _ImagePullSheetState();
}

class _ImagePullSheetState extends ConsumerState<_ImagePullSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _useAuth = false;
  bool _pulling = false;
  bool _done = false;

  /// 回退到 HTTP 阻塞拉取（无逐层进度）。
  bool _fallbackMode = false;

  String _statusText = '';
  String? _error;

  /// 逐层进度：layerId -> 状态文本。
  final Map<String, _LayerProgress> _layers = {};

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

  @override
  void dispose() {
    _subscription?.cancel();
    _channel?.sink.close();
    _nameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// 参与进度统计的层（Docker 的层 ID 至少 8 位，短 id 是状态行不是层）。
  Iterable<_LayerProgress> get _countedLayers =>
      _layers.values.where((l) => l.id.length >= 8);

  /// 已完成的层数（含镜像里本来就有的层）。
  int get _completedLayers => _countedLayers
      .where((l) => l.status == 'Pull complete' || l.status == 'Already exists')
      .length;

  double get _progressValue {
    final total = _countedLayers.length;
    if (total == 0) return 0;
    return _completedLayers / total;
  }

  Future<void> _start() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final name = _nameController.text.trim();
    final server = ref.read(activeServerProvider);

    setState(() {
      _pulling = true;
      _done = false;
      _error = null;
      _layers.clear();
      _fallbackMode = false;
      _statusText = '正在连接…';
    });

    if (server == null) {
      setState(() {
        _pulling = false;
        _error = '尚未选择服务器';
      });
      return;
    }

    try {
      final channel = await wsConnect(server, '/ws/container/image/pull');
      if (!mounted) {
        unawaited(channel.sink.close());
        return;
      }
      _channel = channel;
      channel.sink.add(
        jsonEncode({
          'name': name,
          'auth': _useAuth,
          'username': _useAuth ? _usernameController.text : '',
          'password': _useAuth ? _passwordController.text : '',
        }),
      );
      setState(() => _statusText = '正在拉取 $name …');
      _subscription = channel.stream.listen(
        _onMessage,
        onError: (Object error) {
          if (!mounted) return;
          setState(() {
            _pulling = false;
            _error = describeError(error);
          });
        },
        onDone: () {
          if (!mounted || _done) return;
          setState(() {
            _pulling = false;
            if (_error == null) {
              // 服务端没发 complete 就断开：不能断言成功，让用户回列表确认。
              _done = true;
              _statusText = '连接已结束，请回到镜像列表确认「$name」是否已拉取。';
            }
          });
        },
      );
    } on WsAuthException catch (error) {
      // 未配置面板账号密码：回退到 HTTP 拉取（无进度）。
      if (!mounted) return;
      setState(() {
        _fallbackMode = true;
        _statusText = '${describeError(error)}\n已改用普通模式拉取（无实时进度）…';
      });
      await _pullOverHttp(name);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _pulling = false;
        _error = describeError(error);
      });
    }
  }

  Future<void> _pullOverHttp(String name) async {
    try {
      await ref
          .read(containerRepoProvider)
          .pullImage(
            name: name,
            auth: _useAuth,
            username: _usernameController.text,
            password: _passwordController.text,
          );
      if (!mounted) return;
      setState(() {
        _pulling = false;
        _done = true;
        _statusText = '镜像 $name 拉取完成';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _pulling = false;
        _error =
            '${describeError(error)}\n'
            '（若为超时，镜像可能仍在服务器后台拉取，可稍后刷新列表确认）';
      });
    }
  }

  void _onMessage(dynamic message) {
    final text = message is String
        ? message
        : message is List<int>
        ? const Utf8Decoder(allowMalformed: true).convert(message)
        : '$message';
    if (text.trim().isEmpty) return;

    dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      return;
    }
    final map = asMap(decoded);
    if (map.isEmpty) return;

    final error = asString(map['error']);
    if (error.isNotEmpty || asString(map['status']) == 'error') {
      setState(() {
        _pulling = false;
        _error = error.isEmpty ? '拉取失败' : error;
      });
      return;
    }

    if (asBool(map['complete'])) {
      setState(() {
        _pulling = false;
        _done = true;
        _statusText = '镜像 ${_nameController.text.trim()} 拉取完成';
      });
      return;
    }

    final status = asString(map['status']);
    final id = asString(map['id']);
    final detail = asMap(map['progressDetail']);
    final current = asInt(detail['current']);
    final total = asInt(detail['total']);

    setState(() {
      if (id.isEmpty) {
        if (status.isNotEmpty) _statusText = status;
      } else {
        _layers[id] = _LayerProgress(
          id: id,
          status: status,
          current: current,
          total: total,
        );
      }
    });
  }

  /// 关闭面板。拉取在途时先确认——关闭只会断开进度订阅，
  /// 服务器上的拉取不一定随之中止。
  Future<void> _close() async {
    final navigator = Navigator.of(context);
    if (_pulling) {
      final ok = await showConfirmDialog(
        context,
        title: '关闭拉取面板',
        content:
            '关闭后将不再显示拉取进度，服务器上的拉取可能仍在继续。'
            '稍后可在镜像列表下拉刷新确认结果。确定关闭吗？',
        confirmText: '关闭',
        cancelText: '继续等待',
      );
      if (!ok) return;
    }
    if (navigator.mounted) navigator.pop(_done);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final server = ref.watch(activeServerProvider);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final countedLayers = _countedLayers.length;

    // canPop 恒为 false：一律走 _close()，既能在拉取途中二次确认，
    // 又能保证退出时把 _done 作为结果带回去（maybePop 会丢掉返回值，
    // 拉取成功后列表就不会刷新）。
    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (context, scrollController) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('拉取镜像', style: theme.textTheme.titleMedium),
                    ),
                    A11yIconButton(
                      tooltip: '关闭拉取面板',
                      icon: const Icon(Icons.close),
                      onPressed: _close,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  children: [
                    Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            controller: _nameController,
                            enabled: !_pulling,
                            autofocus: true,
                            decoration: const InputDecoration(
                              labelText: '镜像名称',
                              hintText: '如 nginx:alpine',
                            ),
                            validator: (value) =>
                                (value ?? '').trim().isEmpty ? '请输入镜像名称' : null,
                          ),
                          const SizedBox(height: 12),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('使用仓库账号'),
                            subtitle: const Text('拉取私有仓库镜像时开启'),
                            value: _useAuth,
                            onChanged: _pulling
                                ? null
                                : (value) => setState(() => _useAuth = value),
                          ),
                          if (_useAuth) ...[
                            TextFormField(
                              controller: _usernameController,
                              enabled: !_pulling,
                              decoration: const InputDecoration(
                                labelText: '仓库用户名',
                              ),
                              validator: (value) =>
                                  _useAuth && (value ?? '').trim().isEmpty
                                  ? '请输入仓库用户名'
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _passwordController,
                              enabled: !_pulling,
                              obscureText: true,
                              decoration: const InputDecoration(
                                labelText: '仓库密码',
                              ),
                              validator: (value) =>
                                  _useAuth && (value ?? '').isEmpty
                                  ? '请输入仓库密码'
                                  : null,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_statusText.isNotEmpty)
                      Text(
                        _statusText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    if (_pulling) ...[
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        // 回退模式与尚未收到层信息时无从计算比例，走不确定进度条。
                        value: _fallbackMode || countedLayers == 0
                            ? null
                            : _progressValue,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _fallbackMode
                            ? '普通模式没有逐层进度，请耐心等待…'
                            : countedLayers == 0
                            ? '正在获取镜像层信息…'
                            : '已完成 $_completedLayers / $countedLayers 层',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (_layers.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 200),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.all(10),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final layer in _layers.values)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    layer.display,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontFamily: 'monospace',
                                      fontFamilyFallback: const ['Courier'],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _error!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                    if (_fallbackMode && server != null) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop(_done);
                            context.push(
                              '/servers/edit?id=${server.id}&advanced=1',
                            );
                          },
                          icon: const Icon(Icons.settings_outlined),
                          label: const Text('补填面板账号以查看实时进度'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    if (_done)
                      FilledButton.icon(
                        onPressed: () => Navigator.of(context).pop(true),
                        icon: const Icon(Icons.check),
                        label: const Text('完成'),
                      )
                    else
                      FilledButton.icon(
                        onPressed: _pulling ? null : _start,
                        icon: _pulling
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                ),
                              )
                            : const Icon(Icons.download_outlined),
                        label: Text(_pulling ? '拉取中…' : '开始拉取'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LayerProgress {
  const _LayerProgress({
    required this.id,
    required this.status,
    required this.current,
    required this.total,
  });

  final String id;

  /// Docker 原始状态文本（英文），进度统计按它判断，展示时才翻译。
  final String status;
  final int current;
  final int total;

  String get display {
    final label = _layerStatusLabel(status);
    if (total > 0 && current > 0) {
      final percent = (current / total * 100).clamp(0, 100).toStringAsFixed(0);
      return '$id  $label  $percent%  '
          '${formatBytes(current, fractionDigits: 1)} / '
          '${formatBytes(total, fractionDigits: 1)}';
    }
    return '$id  $label';
  }
}

/// Docker 推送的层状态是英文，UI 全中文，这里统一翻译；
/// 未收录的状态原样展示，不隐藏信息。
String _layerStatusLabel(String status) {
  switch (status) {
    case 'Pulling fs layer':
      return '准备下载';
    case 'Waiting':
      return '排队等待';
    case 'Downloading':
      return '下载中';
    case 'Verifying Checksum':
      return '校验中';
    case 'Download complete':
      return '下载完成';
    case 'Extracting':
      return '解压中';
    case 'Pull complete':
      return '已完成';
    case 'Already exists':
      return '已存在';
    case 'Retrying':
      return '重试中';
    default:
      return status;
  }
}
