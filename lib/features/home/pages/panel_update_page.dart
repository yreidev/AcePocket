import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/ws_client.dart';
import '../../../core/storage/server_store.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/section_card.dart';
import '../models/update_models.dart';
import '../providers/home_providers.dart';
import '../widgets/info_row.dart';
import '../widgets/update_log_list.dart';
import '../widgets/upgrade_log_view.dart';

/// 面板升级页（`/panel/update`）。
///
/// - `GET  /home/update_info` —— 当前版本之后的所有版本与更新日志；
/// - `POST /home/update` —— 无进度输出的同步升级（兜底）；
/// - WebSocket `/ws/panel/update` —— 实时推送升级进度
///   （`{"status":"progress|error|success","msg":"…"}`，见 internal/service/ws.go
///   的 `PanelUpdate`），升级成功后由面板自身重启。
///
/// WS 走面板会话 Cookie 认证：未填写面板账号密码时 [wsConnect] 抛
/// [WsAuthException]，此处提示用户补填，并提供「无日志升级」兜底。
class PanelUpdatePage extends ConsumerStatefulWidget {
  const PanelUpdatePage({super.key});

  @override
  ConsumerState<PanelUpdatePage> createState() => _PanelUpdatePageState();
}

class _PanelUpdatePageState extends ConsumerState<PanelUpdatePage> {
  final List<UpgradeLogEntry> _logs = [];

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

  /// 是否已经进入升级流程（进入后页面从「版本信息」切换为「升级日志」）。
  bool _started = false;
  bool _running = false;
  bool _finished = false;
  String? _error;

  /// 需要用户去服务器配置里补填面板账号密码时的提示。
  String? _authHint;

  /// WS 握手被面板拒绝（前置检查未通过）时的提示。
  bool _handshakeRejected = false;

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_channel?.sink.close());
    super.dispose();
  }

  void _append(UpgradeLogLevel level, String message) {
    if (!mounted || message.isEmpty) return;
    setState(() => _logs.add(UpgradeLogEntry(level, message, DateTime.now())));
  }

  // ---------------------------------------------------------------------------
  // 升级流程
  // ---------------------------------------------------------------------------

  Future<bool> _confirm(String targetVersion) {
    return showConfirmDialog(
      context,
      title: '升级面板',
      content:
          '将把面板升级到 $targetVersion。\n\n'
          '· 升级过程中面板会自动重启，期间管理界面与 API 短暂不可用；\n'
          '· 网站、数据库、容器等业务服务不受影响；\n'
          '· 面板有后台任务正在运行时会拒绝升级；\n'
          '· 升级失败可能需要登录服务器手动修复，请确保已做好备份。\n\n'
          '确定现在升级吗？',
      confirmText: '确认升级',
      danger: true,
    );
  }

  Future<void> _startUpgrade(String targetVersion) async {
    if (_running) return;
    if (!await _confirm(targetVersion)) return;
    if (!mounted) return;

    setState(() {
      _started = true;
      _running = true;
      _finished = false;
      _error = null;
      _authHint = null;
      _handshakeRejected = false;
      _logs.clear();
    });
    await _runWebSocket();
  }

  Future<void> _retry() async {
    if (_running) return;
    setState(() {
      _running = true;
      _error = null;
      _authHint = null;
      _handshakeRejected = false;
      _logs.clear();
    });
    await _runWebSocket();
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

    _append(UpgradeLogLevel.info, '正在连接面板实时通道…');
    try {
      final channel = await wsConnect(server, '/ws/panel/update');
      // 连接 /ws/panel/update 即触发面板升级。建连期间用户可能已退出页面
      // （此时 _channel 仍为 null，dispose 关不到这条连接），必须在此立即
      // 关闭，避免泄漏的连接在后台持续接收升级日志。
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
      _append(UpgradeLogLevel.info, '已连接，面板开始执行升级');

      _subscription = channel.stream.listen(
        _onMessage,
        onError: (Object error) {
          _append(UpgradeLogLevel.error, '连接异常：${_describe(error)}');
          if (!mounted) return;
          setState(() {
            _running = false;
            _error = _describe(error);
          });
        },
        onDone: () {
          if (!mounted) return;
          if (_finished || _error != null) {
            setState(() => _running = false);
            return;
          }
          // 面板升级成功后会立刻重启，连接被动断开属于常见收尾情况。
          _append(UpgradeLogLevel.error, '连接已断开，升级结果未知，请稍后刷新面板确认版本');
          setState(() {
            _running = false;
            _error = '连接已断开，升级结果未知';
          });
        },
        cancelOnError: true,
      );
    } on WsAuthException catch (e) {
      if (!mounted) return;
      _append(UpgradeLogLevel.error, e.message);
      setState(() {
        _running = false;
        _authHint = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      final message = _describe(e);
      _append(UpgradeLogLevel.error, '连接失败：$message');
      setState(() {
        _running = false;
        _error = message;
        // 面板在 WS 握手前做前置检查（离线模式 / 有后台任务 / 拉取版本失败），
        // 不通过时直接返回 HTTP 错误、不升级协议，客户端只能看到握手失败。
        _handshakeRejected = true;
      });
    }
  }

  void _onMessage(dynamic raw) {
    final text = raw is String ? raw : utf8.decode(List<int>.from(raw as List));
    dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      _append(UpgradeLogLevel.progress, text);
      return;
    }
    if (decoded is! Map) {
      _append(UpgradeLogLevel.progress, text);
      return;
    }
    final status = '${decoded['status'] ?? ''}';
    final message = '${decoded['msg'] ?? ''}';
    switch (status) {
      case 'progress':
        _append(UpgradeLogLevel.progress, message);
      case 'success':
        _append(UpgradeLogLevel.success, '升级完成，面板正在重启');
        _onFinished();
      case 'error':
        final text = message.isEmpty ? '升级失败' : message;
        _append(UpgradeLogLevel.error, text);
        if (mounted) {
          setState(() {
            _running = false;
            _error = text;
          });
        }
      default:
        if (message.isNotEmpty) _append(UpgradeLogLevel.progress, message);
    }
  }

  void _onFinished() {
    ref.invalidate(panelUpdateProvider);
    ref.invalidate(panelUpdateInfoProvider);
    ref.invalidate(systemInfoProvider);
    ref.invalidate(panelInfoProvider);
    if (!mounted) return;
    setState(() {
      _finished = true;
      _running = false;
      _error = null;
    });
  }

  /// 兜底：直接调用 `POST /home/update`（无进度输出，返回即已完成或失败）。
  Future<void> _upgradeWithoutLogs() async {
    if (_running) return;
    setState(() {
      _started = true;
      _running = true;
      _error = null;
      _authHint = null;
      _handshakeRejected = false;
    });
    _append(UpgradeLogLevel.info, '正在通过 HTTP 接口升级，期间无进度输出，请耐心等待…');
    try {
      await ref.read(homeRepoProvider).update();
      _append(UpgradeLogLevel.success, '升级完成，面板正在重启');
      _onFinished();
    } catch (e) {
      final message = _describe(e);
      _append(UpgradeLogLevel.error, message);
      if (mounted) {
        setState(() {
          _running = false;
          _error = message;
        });
      }
    }
  }

  Future<bool> _confirmLeave() async {
    if (!_running) return true;
    return showConfirmDialog(
      context,
      title: '升级进行中',
      content: '离开页面只会断开日志连接，面板端的升级仍会继续执行。确定离开吗？',
      confirmText: '离开',
      danger: true,
    );
  }

  static String _describe(Object error) {
    if (error is ApiException) return error.message;
    if (error is WsAuthException) return error.message;
    return error.toString().replaceFirst(RegExp(r'^\w+Exception:\s*'), '');
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final server = ref.watch(activeServerProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _confirmLeave()) {
          if (context.mounted) context.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('面板升级'),
          leading: A11yIconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: '返回上一页',
            onPressed: () async {
              if (await _confirmLeave()) {
                if (context.mounted) context.pop();
              }
            },
          ),
          actions: [
            if (!_started)
              A11yIconButton(
                tooltip: '重新检查面板版本',
                icon: const Icon(Icons.refresh),
                onPressed: () {
                  ref.invalidate(panelUpdateInfoProvider);
                  ref.invalidate(systemInfoProvider);
                  ref.invalidate(panelUpdateProvider);
                },
              ),
          ],
        ),
        body: server == null
            ? const EmptyView(icon: Icons.dns_outlined, message: '还没有配置任何服务器')
            : _started
            ? _buildUpgradeView()
            : _buildInfoView(),
      ),
    );
  }

  /// 未开始升级：展示当前版本 + 更新日志 + 升级入口。
  Widget _buildInfoView() {
    final theme = Theme.of(context);
    final systemInfo = ref.watch(systemInfoProvider);
    final updateInfo = ref.watch(panelUpdateInfoProvider);
    final currentVersion = systemInfo.valueOrNull?.panelVersion ?? '';

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(panelUpdateInfoProvider);
        ref.invalidate(systemInfoProvider);
        ref.invalidate(panelUpdateProvider);
        await ref
            .read(panelUpdateInfoProvider.future)
            .catchError((Object _) => const <PanelVersion>[]);
      },
      child: updateInfo.when(
        loading: () => _scrollFill(const LoadingView(message: '正在获取更新信息…')),
        error: (error, _) => _scrollFill(_buildUpdateError(error)),
        data: (versions) {
          final latest = versions.isEmpty ? '' : versions.first.version;
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: 4, bottom: 24),
            children: [
              SectionCard(
                title: '版本',
                child: Column(
                  children: [
                    InfoRow(
                      label: '当前版本',
                      value: currentVersion,
                      monospace: true,
                    ),
                    InfoRow(
                      label: '可升级到',
                      value: latest,
                      monospace: true,
                      valueColor: theme.colorScheme.primary,
                    ),
                    InfoRow(label: '待更新版本数', value: '${versions.length}'),
                  ],
                ),
              ),
              if (versions.isEmpty)
                SectionCard(
                  child: Text(
                    '面板未返回可更新的版本信息。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                UpdateLogList(versions: versions),
              SectionCard(
                title: '升级须知',
                child: Text(
                  '升级会下载对应架构的新版本程序并替换当前面板，完成后面板自动重启，'
                  '期间管理界面与 API 短暂不可用，网站与数据库等业务服务不受影响。\n'
                  '面板有后台任务正在运行时会拒绝升级；升级前建议先做一次面板备份。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: FilledButton.icon(
                  onPressed: versions.isEmpty
                      ? null
                      : () => _startUpgrade(latest),
                  icon: const Icon(Icons.system_update_alt_rounded),
                  label: Text(versions.isEmpty ? '暂无可用升级' : '升级到 $latest'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildUpdateError(Object error) {
    final message = _describe(error);
    // 面板对「已是最新版本」也返回错误状态码，这里转成正向提示。
    final isLatest =
        message.contains('最新版本') ||
        message.toLowerCase().contains('latest version');
    if (isLatest) {
      return EmptyView(
        icon: Icons.verified_outlined,
        message: '当前已是最新版本，无需升级',
        action: FilledButton.tonalIcon(
          onPressed: () {
            ref.invalidate(panelUpdateInfoProvider);
            ref.invalidate(panelUpdateProvider);
          },
          icon: const Icon(Icons.refresh),
          label: const Text('重新检查'),
        ),
      );
    }
    return ErrorView(
      error: error,
      onRetry: () => ref.invalidate(panelUpdateInfoProvider),
    );
  }

  /// 升级中 / 已结束：展示实时日志与后续操作。
  Widget _buildUpgradeView() {
    final theme = Theme.of(context);
    return Column(
      children: [
        if (_authHint != null) _buildAuthHint(theme),
        if (_handshakeRejected && _authHint == null) _buildRejectedHint(theme),
        Expanded(child: UpgradeLogView(logs: _logs)),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: _buildBottomAction(),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomAction() {
    if (_finished) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '面板正在重启，稍后刷新即可看到新版本。',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.check),
            label: const Text('完成'),
          ),
        ],
      );
    }
    if (_running) {
      return FilledButton.icon(
        onPressed: null,
        icon: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        label: const Text('升级中…'),
      );
    }
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _upgradeWithoutLogs,
            icon: const Icon(Icons.bolt_outlined, size: 18),
            label: const Text('无日志升级'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            onPressed: _retry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('重试'),
          ),
        ),
      ],
    );
  }

  Widget _buildAuthHint(ThemeData theme) {
    return SectionCard(
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
                  '实时升级日志需要面板会话认证。请到「服务器配置」中补填面板登录用户名与密码后重试，'
                  '或使用下方的「无日志升级」。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Builder(
              builder: (context) {
                final server = ref.read(activeServerProvider);
                if (server == null) return const SizedBox.shrink();
                return TextButton.icon(
                  onPressed: () =>
                      context.push('/servers/edit?id=${server.id}&advanced=1'),
                  icon: const Icon(Icons.manage_accounts_outlined, size: 18),
                  label: const Text('去填写面板账号'),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRejectedHint(ThemeData theme) {
    return SectionCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20, color: theme.colorScheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '面板未接受实时升级连接。常见原因：开启了离线模式、有后台任务正在运行，'
              '或获取最新版本失败。可点击「无日志升级」查看面板返回的具体原因。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 让 loading / error 视图也能被下拉刷新。
  Widget _scrollFill(Widget child) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.6,
          child: Center(child: child),
        ),
      ],
    );
  }
}
