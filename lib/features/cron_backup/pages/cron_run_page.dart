import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/api/ws_client.dart';
import '../../../core/storage/server_store.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/error_view.dart';
import '../widgets/feedback.dart';
import '../widgets/format.dart';
import '../widgets/no_server_view.dart';

/// 计划任务「立即执行」页（`/crons/run?shell=<脚本路径>&name=<任务名>`）。
///
/// 通过 WebSocket `/api/ws/exec` 执行 `bash '<脚本路径>'` 并实时回显输出。
/// WS 走面板会话认证（Cookie），未配置面板账号时提示用户去补填。
class CronRunPage extends ConsumerStatefulWidget {
  const CronRunPage({super.key, required this.shell, this.name = ''});

  /// 服务端脚本文件绝对路径。
  final String shell;

  /// 任务名称。
  final String name;

  @override
  ConsumerState<CronRunPage> createState() => _CronRunPageState();
}

enum _RunStatus { connecting, running, finished, failed }

class _CronRunPageState extends ConsumerState<CronRunPage> {
  final ScrollController _scrollController = ScrollController();

  final List<String> _lines = [];
  _RunStatus _status = _RunStatus.connecting;
  Object? _error;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

  String get _command => "bash '${widget.shell}'";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _closeChannel();
    _scrollController.dispose();
    super.dispose();
  }

  void _closeChannel() {
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
  }

  Future<void> _start() async {
    final server = ref.read(activeServerProvider);
    if (server == null) return;
    setState(() {
      _status = _RunStatus.connecting;
      _error = null;
      _lines.clear();
    });
    try {
      final channel = await wsConnect(server, '/ws/exec');
      if (!mounted) {
        await channel.sink.close();
        return;
      }
      _channel = channel;
      _subscription = channel.stream.listen(
        _onData,
        onError: (Object error) {
          if (!mounted) return;
          setState(() {
            _status = _RunStatus.failed;
            _error = error;
          });
        },
        onDone: () {
          if (!mounted) return;
          setState(() {
            if (_status != _RunStatus.failed) _status = _RunStatus.finished;
          });
        },
      );
      // 第一条消息即为要执行的命令。
      channel.sink.add(_command);
      setState(() => _status = _RunStatus.running);
    } on WsAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _RunStatus.failed;
        _error = e;
      });
      await _showWsAuthDialog(e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _RunStatus.failed;
        _error = e;
      });
    }
  }

  void _onData(dynamic data) {
    String text;
    if (data is String) {
      text = data;
    } else if (data is List<int>) {
      text = utf8.decode(data, allowMalformed: true);
    } else {
      return;
    }
    // exec 通道每行一条消息（服务端按行 scan 后逐条 Write），
    // 这里仍按换行切分以兼容一条消息包含多行的情况。
    final parts = stripAnsi(text).split('\n');
    if (parts.isNotEmpty && parts.last.isEmpty) parts.removeLast();
    if (parts.isEmpty) return;
    setState(() {
      for (final part in parts) {
        _lines.add(part.replaceAll('\r', ''));
      }
      // 避免长时间输出导致内存无限增长。
      if (_lines.length > 5000) {
        _lines.removeRange(0, _lines.length - 5000);
      }
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  void _stop() {
    _closeChannel();
    setState(() => _status = _RunStatus.finished);
    showInfoSnack(context, '已断开连接（服务端命令可能仍在运行）');
  }

  Future<void> _showWsAuthDialog(String message) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('无法执行任务'),
        content: Text(
          '$message\n\n'
          '立即执行走面板会话认证，需要在「服务器配置」中补充面板登录用户名与密码。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _copyAll() async {
    await Clipboard.setData(ClipboardData(text: _lines.join('\n')));
    if (mounted) showSuccessSnack(context, '输出已复制到剪贴板');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final server = ref.watch(activeServerProvider);
    final running =
        _status == _RunStatus.connecting || _status == _RunStatus.running;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('立即执行'),
            if (widget.name.isNotEmpty)
              Text(
                widget.name,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        actions: [
          A11yIconButton(
            tooltip: '复制全部输出',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: _lines.isEmpty ? null : _copyAll,
          ),
          A11yIconButton(
            tooltip: running ? '断开连接' : '重新执行任务',
            icon: Icon(running ? Icons.stop_circle_outlined : Icons.refresh),
            onPressed: server == null ? null : (running ? _stop : _start),
          ),
        ],
      ),
      body: server == null
          ? const NoServerView()
          : Column(
              children: [
                _StatusBar(status: _status, command: _command),
                if (_status == _RunStatus.failed && _lines.isEmpty)
                  Expanded(
                    child: ErrorView(error: _error ?? '执行失败', onRetry: _start),
                  )
                else if (_lines.isEmpty)
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          running ? '正在等待命令输出…' : '本次执行没有任何输出',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: SelectionArea(
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                        itemCount: _lines.length,
                        itemBuilder: (context, index) {
                          final line = _lines[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1),
                            child: Text(
                              line.isEmpty ? ' ' : line,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                height: 1.35,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.status, required this.command});

  final _RunStatus status;
  final String command;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    late final Color background;
    late final Color foreground;
    late final String text;
    switch (status) {
      case _RunStatus.connecting:
        background = colorScheme.secondaryContainer;
        foreground = colorScheme.onSecondaryContainer;
        text = '正在连接面板…';
        break;
      case _RunStatus.running:
        background = colorScheme.primaryContainer;
        foreground = colorScheme.onPrimaryContainer;
        text = '执行中…';
        break;
      case _RunStatus.finished:
        background = colorScheme.surfaceContainerHighest;
        foreground = colorScheme.onSurfaceVariant;
        text = '已结束';
        break;
      case _RunStatus.failed:
        background = colorScheme.errorContainer;
        foreground = colorScheme.onErrorContainer;
        text = '执行失败';
        break;
    }
    return Container(
      width: double.infinity,
      color: background,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: theme.textTheme.labelMedium?.copyWith(color: foreground),
          ),
          const SizedBox(height: 2),
          Text(
            command,
            style: theme.textTheme.bodySmall?.copyWith(
              color: foreground,
              fontFamily: 'monospace',
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
