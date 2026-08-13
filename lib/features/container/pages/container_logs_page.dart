import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/ws_client.dart';
import '../../../core/models/server.dart';
import '../../../core/storage/server_store.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/error_view.dart';

/// 容器实时日志页（`/containers/:id/logs`）。
///
/// 通过 `GET /api/ws/follow?container=<id>` 订阅（源码
/// `internal/service/ws.go` 的 `Follow` -> `followContainer`）。
/// 服务端以 `Tail=0` 打开日志流，**只推送接入之后产生的新日志**。
///
/// WS 只接受会话 Cookie 认证，未在服务器配置中填写面板账号密码时
/// [wsConnect] 抛 [WsAuthException]，此处捕获并引导用户去补填。
class ContainerLogsPage extends ConsumerStatefulWidget {
  const ContainerLogsPage({super.key, required this.id});

  final String id;

  @override
  ConsumerState<ContainerLogsPage> createState() => _ContainerLogsPageState();
}

class _ContainerLogsPageState extends ConsumerState<ContainerLogsPage> {
  /// 最多保留的日志行数，避免长时间跟踪导致内存无限增长。
  static const int _maxLines = 2000;

  final List<String> _lines = [];
  final ScrollController _scrollController = ScrollController();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

  /// 未成行的残留片段（WS 消息不保证按行切分）。
  String _pending = '';

  bool _connecting = true;
  bool _closed = false;
  bool _autoScroll = true;
  Object? _error;

  /// 认证失败（需要补填面板账号密码）。
  bool _needCredentials = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }

  @override
  void dispose() {
    _disconnect();
    _scrollController.dispose();
    super.dispose();
  }

  void _disconnect() {
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
  }

  Future<void> _connect() async {
    final server = ref.read(activeServerProvider);
    if (server == null) {
      setState(() {
        _connecting = false;
        _error = const WsAuthException('尚未选择服务器');
      });
      return;
    }

    setState(() {
      _connecting = true;
      _closed = false;
      _error = null;
      _needCredentials = false;
    });

    try {
      final channel = await wsConnect(
        server,
        '/ws/follow',
        query: {'container': widget.id},
      );
      if (!mounted) {
        unawaited(channel.sink.close());
        return;
      }
      _channel = channel;
      _subscription = channel.stream.listen(
        _onMessage,
        onError: (Object error) {
          if (!mounted) return;
          setState(() {
            _error = error;
            _connecting = false;
            _closed = true;
          });
        },
        onDone: () {
          if (!mounted) return;
          setState(() {
            _closed = true;
            _connecting = false;
          });
        },
        cancelOnError: true,
      );
      setState(() => _connecting = false);
    } on WsAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _closed = true;
        _error = error;
        _needCredentials = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _closed = true;
        _error = error;
      });
    }
  }

  void _onMessage(dynamic message) {
    final String text;
    if (message is String) {
      text = message;
    } else if (message is List<int>) {
      text = const Utf8Decoder(allowMalformed: true).convert(message);
    } else {
      text = '$message';
    }
    if (text.isEmpty) return;

    final combined = _pending + text.replaceAll('\r\n', '\n');
    final parts = combined.split('\n');
    _pending = parts.removeLast();

    if (parts.isEmpty) return;
    setState(() {
      for (final line in parts) {
        _lines.add(_stripAnsi(line));
      }
      if (_lines.length > _maxLines) {
        _lines.removeRange(0, _lines.length - _maxLines);
      }
    });
    _scheduleScroll();
  }

  void _scheduleScroll() {
    if (!_autoScroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  /// 距底部多少像素以内算「贴着底部」。
  static const double _bottomThreshold = 24;

  /// 用户手动滚动与自动滚动的冲突处理。
  ///
  /// 之前只要有新日志就无条件 `jumpTo` 到底部，用户往上翻看历史时会被
  /// 反复拽回底部，根本读不完一行。现在：手指往上拖离底部即暂停自动滚动，
  /// 重新滚回底部（含惯性滑动结束时）自动恢复。
  ///
  /// 只认 `dragDetails != null` 的滚动更新（即真正的手指拖动），
  /// 程序化的 `jumpTo` 不会被误判为用户操作。
  bool _onScrollNotification(ScrollNotification notification) {
    final metrics = notification.metrics;
    final atBottom =
        metrics.pixels >= metrics.maxScrollExtent - _bottomThreshold;

    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      if (atBottom != _autoScroll) setState(() => _autoScroll = atBottom);
    } else if (notification is ScrollEndNotification &&
        atBottom &&
        !_autoScroll) {
      setState(() => _autoScroll = true);
    }
    return false;
  }

  /// 去掉 ANSI 控制序列（面板日志可能带颜色码）。
  static String _stripAnsi(String input) =>
      input.replaceAll(RegExp(r'\x1B\[[0-9;?]*[ -/]*[@-~]'), '');

  Future<void> _reconnect() async {
    _disconnect();
    _pending = '';
    await _connect();
  }

  /// 清空已接收的日志。
  ///
  /// 面板只推送接入之后产生的日志，清空后这些内容无法再取回，
  /// 因此有内容时先二次确认。
  Future<void> _clear() async {
    if (_lines.isEmpty) return;
    final ok = await showConfirmDialog(
      context,
      title: '清空日志',
      content:
          '将清空已接收的 ${_lines.length} 行日志。'
          '面板只推送接入之后产生的日志，清空后无法找回。确定继续吗？',
      confirmText: '清空',
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() {
      _lines.clear();
      _pending = '';
    });
  }

  Future<void> _copyAll() async {
    if (_lines.isEmpty) {
      showInfoSnack(context, '暂无可复制的日志');
      return;
    }
    await Clipboard.setData(ClipboardData(text: _lines.join('\n')));
    if (!mounted) return;
    showSuccessSnack(context, '已复制 ${_lines.length} 行日志');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final server = ref.watch(activeServerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('实时日志'),
        actions: [
          // 图标表示「按下会做什么」：跟随中显示暂停，暂停中显示回到底部。
          A11yIconButton(
            tooltip: _autoScroll ? '暂停自动滚动' : '恢复自动滚动并回到底部',
            icon: Icon(
              _autoScroll
                  ? Icons.pause_circle_outline
                  : Icons.vertical_align_bottom,
            ),
            onPressed: () {
              setState(() => _autoScroll = !_autoScroll);
              _scheduleScroll();
            },
          ),
          A11yIconButton(
            tooltip: '复制全部日志',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: _lines.isEmpty ? null : _copyAll,
          ),
          A11yIconButton(
            tooltip: '清空日志',
            icon: const Icon(Icons.clear_all),
            onPressed: _lines.isEmpty ? null : _clear,
          ),
          A11yIconButton(
            tooltip: '重新连接日志流',
            icon: const Icon(Icons.refresh),
            onPressed: _connecting ? null : _reconnect,
          ),
        ],
      ),
      body: Column(
        children: [
          _StatusBar(
            connecting: _connecting,
            closed: _closed,
            lineCount: _lines.length,
            autoScroll: _autoScroll,
          ),
          Expanded(child: _buildBody(theme, server)),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme, ServerConfig? server) {
    if (_error != null && _lines.isEmpty) {
      if (_needCredentials) {
        return _CredentialHint(
          message: describeError(_error!),
          onGoToSettings: server == null
              ? null
              : () => context.push('/servers/edit?id=${server.id}&advanced=1'),
          onRetry: _reconnect,
        );
      }
      return ErrorView(error: _error!, onRetry: _reconnect);
    }

    if (_connecting && _lines.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(height: 16),
            Text('正在连接日志流…'),
          ],
        ),
      );
    }

    if (_lines.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.subject_outlined,
                size: 48,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                '等待新日志输出…\n面板只推送接入之后产生的日志，历史日志请在服务器上查看。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      color: theme.colorScheme.surfaceContainerLowest,
      child: SelectionArea(
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScrollNotification,
          child: Scrollbar(
            controller: _scrollController,
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: _lines.length,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Text(
                  _lines[index],
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontFamilyFallback: const ['Courier'],
                    height: 1.45,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.connecting,
    required this.closed,
    required this.lineCount,
    required this.autoScroll,
  });

  final bool connecting;
  final bool closed;
  final int lineCount;
  final bool autoScroll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color) = connecting
        ? ('连接中', theme.colorScheme.onSurfaceVariant)
        : closed
        ? ('已断开', theme.colorScheme.error)
        : ('已连接', theme.colorScheme.primary);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: theme.colorScheme.surfaceContainerHigh,
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(color: color),
          ),
          const SizedBox(width: 16),
          Text(
            '$lineCount 行',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          Text(
            autoScroll ? '自动滚动中' : '已暂停自动滚动',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// WS 会话认证失败提示：引导用户补填面板账号密码。
class _CredentialHint extends StatelessWidget {
  const _CredentialHint({
    required this.message,
    required this.onRetry,
    this.onGoToSettings,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback? onGoToSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '实时日志走面板会话（Cookie）认证，API 令牌无法用于 WebSocket，'
              '需要在服务器配置中填写面板登录账号与密码。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              alignment: WrapAlignment.center,
              children: [
                if (onGoToSettings != null)
                  FilledButton.icon(
                    onPressed: onGoToSettings,
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('去补填账号'),
                  ),
                FilledButton.tonalIcon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
