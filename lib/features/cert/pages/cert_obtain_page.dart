import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/api/ws_client.dart';
import '../../../core/storage/server_store.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/section_card.dart';
import '../providers/cert_providers.dart';
import '../widgets/snack.dart';

enum _LogLevel { info, progress, success, error }

class _LogEntry {
  const _LogEntry(this.level, this.message, this.time);

  final _LogLevel level;
  final String message;
  final DateTime time;
}

/// 证书签发 / 续签页 `/certs/:id/obtain?mode=obtain|renew`。
///
/// 通过 WebSocket `/api/ws/cert/obtain`（或 `/api/ws/cert/renew`）实时展示进度：
/// 连接后需先发送 `{"id": <证书 id>}`，服务端随后推送
/// `{"status":"progress|error|success","msg":"…"}`（见 internal/service/ws.go handleCertWs）。
///
/// WS 走面板会话 Cookie 认证，未在服务器配置中填写面板账号密码时
/// [wsConnect] 抛 [WsAuthException]，此处会提示用户补填，并提供
/// 「无日志模式」（HTTP 同步接口）兜底。
class CertObtainPage extends ConsumerStatefulWidget {
  const CertObtainPage({super.key, required this.certId, this.renew = false});

  final int certId;

  /// true 为续签（/ws/cert/renew），false 为签发（/ws/cert/obtain）。
  final bool renew;

  @override
  ConsumerState<CertObtainPage> createState() => _CertObtainPageState();
}

class _CertObtainPageState extends ConsumerState<CertObtainPage> {
  final List<_LogEntry> _logs = [];
  final ScrollController _scrollController = ScrollController();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

  /// 签发方式：true 为自签名（HTTP 接口），false 为 ACME 自动签发（WebSocket）。
  bool _selfSigned = false;

  bool _running = false;
  bool _finished = false;
  bool _changed = false;
  String? _error;

  /// 需要用户去服务器配置里补填面板账号密码时的提示。
  String? _authHint;

  String get _title => widget.renew ? '续签证书' : '签发证书';

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_channel?.sink.close());
    _scrollController.dispose();
    super.dispose();
  }

  void _append(_LogLevel level, String message) {
    if (!mounted) return;
    setState(() => _logs.add(_LogEntry(level, message, DateTime.now())));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _start() async {
    if (_running) return;
    setState(() {
      _running = true;
      _finished = false;
      _error = null;
      _authHint = null;
      _logs.clear();
    });

    if (!widget.renew && _selfSigned) {
      await _runSelfSigned();
      return;
    }
    await _runWebSocket();
  }

  Future<void> _runSelfSigned() async {
    _append(_LogLevel.info, '正在签发自签名证书…');
    try {
      await ref.read(certRepoProvider).obtainSelfSigned(widget.certId);
      _changed = true;
      _append(_LogLevel.success, '自签名证书签发成功');
      if (mounted) setState(() => _finished = true);
    } catch (e) {
      _append(_LogLevel.error, errorMessage(e));
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _runWebSocket() async {
    final server = ref.read(activeServerProvider);
    if (server == null) {
      setState(() {
        _running = false;
        _error = '尚未选择服务器';
      });
      return;
    }

    // 重试时先关掉上一次可能残留的连接与订阅，避免旧 channel 泄漏。
    unawaited(_subscription?.cancel());
    _subscription = null;
    unawaited(_channel?.sink.close());
    _channel = null;

    final path = widget.renew ? '/ws/cert/renew' : '/ws/cert/obtain';
    _append(_LogLevel.info, '正在连接面板实时通道…');

    try {
      final channel = await wsConnect(server, path);
      // 建连最长可等十余秒，期间用户可能已退出页面（此时 _channel 仍为 null，
      // dispose 关不到这条连接）。必须在发送签发指令之前检查并关闭，
      // 否则会在用户以为已取消的情况下触发面板侧的签发 / 续签任务。
      if (!mounted) {
        unawaited(channel.sink.close());
        return;
      }
      await channel.ready;
      if (!mounted) {
        unawaited(channel.sink.close());
        return;
      }
      _channel = channel;
      channel.sink.add(jsonEncode({'id': widget.certId}));
      _append(_LogLevel.info, widget.renew ? '已提交续签请求' : '已提交签发请求');

      _subscription = channel.stream.listen(
        _onMessage,
        onError: (Object error) {
          _append(_LogLevel.error, '连接异常：${errorMessage(error)}');
          if (mounted) {
            setState(() {
              _running = false;
              _error = errorMessage(error);
            });
          }
        },
        onDone: () {
          if (!mounted) return;
          if (!_finished && _error == null) {
            _append(_LogLevel.error, '连接已断开，操作可能未完成');
            setState(() {
              _running = false;
              _error = '连接已断开';
            });
          } else {
            setState(() => _running = false);
          }
        },
        cancelOnError: true,
      );
    } on WsAuthException catch (e) {
      if (!mounted) return;
      _append(_LogLevel.error, e.message);
      setState(() {
        _running = false;
        _authHint = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      _append(_LogLevel.error, errorMessage(e));
      setState(() {
        _running = false;
        _error = errorMessage(e);
      });
    }
  }

  void _onMessage(dynamic raw) {
    final text = raw is String ? raw : utf8.decode(List<int>.from(raw as List));
    dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      _append(_LogLevel.progress, text);
      return;
    }
    if (decoded is! Map) {
      _append(_LogLevel.progress, text);
      return;
    }
    final status = '${decoded['status'] ?? ''}';
    final message = '${decoded['msg'] ?? ''}';
    switch (status) {
      case 'progress':
        _append(_LogLevel.progress, message);
      case 'success':
        _changed = true;
        _append(_LogLevel.success, widget.renew ? '续签成功' : '签发成功');
        if (mounted) {
          setState(() {
            _finished = true;
            _running = false;
          });
        }
      case 'error':
        _append(_LogLevel.error, message.isEmpty ? '操作失败' : message);
        if (mounted) {
          setState(() {
            _error = message.isEmpty ? '操作失败' : message;
            _running = false;
          });
        }
      default:
        if (message.isNotEmpty) _append(_LogLevel.progress, message);
    }
  }

  /// 无实时日志的兜底方案：直接调用 HTTP 同步接口。
  Future<void> _runWithoutLogs() async {
    setState(() {
      _running = true;
      _error = null;
      _authHint = null;
    });
    _append(_LogLevel.info, '正在通过 HTTP 接口执行，期间无进度输出，请耐心等待…');
    try {
      final repo = ref.read(certRepoProvider);
      if (widget.renew) {
        await repo.renew(widget.certId);
      } else {
        await repo.obtainAuto(widget.certId);
      }
      _changed = true;
      _append(_LogLevel.success, widget.renew ? '续签成功' : '签发成功');
      if (mounted) setState(() => _finished = true);
    } catch (e) {
      _append(_LogLevel.error, errorMessage(e));
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<bool> _confirmLeave() async {
    if (!_running) return true;
    return showConfirmDialog(
      context,
      title: '正在执行中',
      content: '离开页面会断开实时日志连接，面板端的签发流程仍会继续。确定离开吗？',
      confirmText: '离开',
      danger: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _confirmLeave()) {
          if (context.mounted) context.pop(_changed);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_title),
          // 走 maybePop 触发上面的 PopScope，和系统返回手势共用同一套确认流程，
          // 避免「箭头有确认、手势没确认」（或反过来）的不一致。
          leading: A11yIconButton(
            tooltip: '返回证书列表',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.maybePop(context),
          ),
        ),
        body: Column(
          children: [
            if (!widget.renew)
              SectionCard(
                title: '签发方式',
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.cloud_done_outlined),
                      label: Text('ACME 自动'),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.shield_outlined),
                      label: Text('自签名'),
                    ),
                  ],
                  selected: {_selfSigned},
                  onSelectionChanged: _running || _finished
                      ? null
                      : (values) => setState(() => _selfSigned = values.first),
                ),
              ),
            if (_authHint != null)
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.lock_outline,
                          size: 20,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '$_authHint\n\n'
                            '实时日志需要面板会话认证。请到「服务器配置」中补填面板登录用户名与密码后重试，'
                            '或改用下方的无日志模式。',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _running ? null : _start,
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('重试连接'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: _running ? null : _runWithoutLogs,
                            icon: const Icon(Icons.play_arrow, size: 18),
                            label: const Text('无日志执行'),
                          ),
                        ),
                      ],
                    ),
                    // 跳转到服务器编辑页补填面板账号（servers 模块约定：
                    // advanced=1 自动展开高级选项并定位到用户名/密码）。
                    Builder(
                      builder: (context) {
                        final server = ref.read(activeServerProvider);
                        if (server == null) return const SizedBox.shrink();
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () => context.push(
                              '/servers/edit?id=${server.id}&advanced=1',
                            ),
                            icon: const Icon(
                              Icons.manage_accounts_outlined,
                              size: 18,
                            ),
                            label: const Text('去填写面板账号'),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _logs.isEmpty
                  ? _IdleHint(renew: widget.renew, selfSigned: _selfSigned)
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: _logs.length,
                      itemBuilder: (context, index) =>
                          _LogRow(entry: _logs[index]),
                    ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: _finished
                    ? Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => context.pop(true),
                              icon: const Icon(Icons.check),
                              label: const Text('完成'),
                            ),
                          ),
                        ],
                      )
                    : FilledButton.icon(
                        onPressed: _running ? null : _start,
                        icon: _running
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                _error == null
                                    ? Icons.play_arrow
                                    : Icons.refresh,
                              ),
                        label: Text(
                          _running
                              ? '执行中…'
                              : _error == null
                              ? (widget.renew ? '开始续签' : '开始签发')
                              : '重试',
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IdleHint extends StatelessWidget {
  const _IdleHint({required this.renew, required this.selfSigned});

  final bool renew;
  final bool selfSigned;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = renew
        ? '点击下方按钮开始续签，面板会实时推送续签日志。'
        : selfSigned
        ? '自签名证书由面板本地生成，仅适用于内网或测试环境，浏览器会提示不受信任。'
        : '点击下方按钮开始签发，面板会通过实时通道推送 ACME 验证与签发日志。\n'
              '签发过程最长 10 分钟，请保持网络畅通。';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              renew ? Icons.autorenew : Icons.verified_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              text,
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
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry});

  final _LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // 级别只靠图标与颜色区分，读屏与色觉障碍用户会漏掉，补一个语义标签。
    final (
      IconData icon,
      Color color,
      String levelLabel,
    ) = switch (entry.level) {
      _LogLevel.info => (
        Icons.info_outline,
        colorScheme.onSurfaceVariant,
        '提示',
      ),
      _LogLevel.progress => (
        Icons.radio_button_checked,
        colorScheme.primary,
        '进行中',
      ),
      _LogLevel.success => (
        Icons.check_circle_outline,
        colorScheme.primary,
        '成功',
      ),
      _LogLevel.error => (Icons.error_outline, colorScheme.error, '失败'),
    };
    final time = entry.time;
    final stamp =
        '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color, semanticLabel: levelLabel),
          const SizedBox(width: 8),
          Text(
            stamp,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.outline,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              entry.message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: entry.level == _LogLevel.error
                    ? colorScheme.error
                    : colorScheme.onSurface,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
