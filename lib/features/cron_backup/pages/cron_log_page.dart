import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/api/ws_client.dart';
import '../../../core/storage/server_store.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../providers/cron_providers.dart';
import '../widgets/feedback.dart';
import '../widgets/format.dart';
import '../widgets/no_server_view.dart';

/// 计划任务日志页（`/crons/log?path=<日志路径>&name=<任务名>`）。
///
/// - 通过 `/api/file/tail` 反向分页读取历史日志；
/// - 可开启「实时跟踪」（WebSocket `/api/ws/follow`，走面板会话认证）；
/// - 可清空日志（`/api/file/truncate`）。
class CronLogPage extends ConsumerStatefulWidget {
  const CronLogPage({super.key, required this.path, this.name = ''});

  /// 服务端日志文件绝对路径。
  final String path;

  /// 任务名称（用于标题展示）。
  final String name;

  @override
  ConsumerState<CronLogPage> createState() => _CronLogPageState();
}

class _CronLogPageState extends ConsumerState<CronLogPage> {
  static const _pageLines = 300;

  final ScrollController _scrollController = ScrollController();

  List<String> _lines = [];

  /// 已通过 `/file/tail` 读到的历史行数。
  ///
  /// 「加载更早的日志」的 offset 必须只算历史行：实时跟踪追加的新行也在
  /// [_lines] 里，用 `_lines.length` 当 offset 会越过尚未读取的历史，
  /// 中间那一段日志永远读不到。
  int _tailLoaded = 0;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;

  bool _following = false;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  String _pending = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _stopFollow();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(cronRepoProvider)
          .tailLog(widget.path, offset: 0, limit: _pageLines);
      if (!mounted) return;
      setState(() {
        _lines = result.lines;
        _tailLoaded = result.lines.length;
        _hasMore = result.hasMore;
        _loading = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  Future<void> _loadEarlier() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final result = await ref
          .read(cronRepoProvider)
          .tailLog(widget.path, offset: _tailLoaded, limit: _pageLines);
      if (!mounted) return;
      setState(() {
        _lines = [...result.lines, ..._lines];
        _tailLoaded += result.lines.length;
        _hasMore = result.hasMore;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      showErrorSnack(context, e);
    }
  }

  Future<void> _toggleFollow() async {
    if (_following) {
      _stopFollow();
      setState(() {});
      return;
    }
    final server = ref.read(activeServerProvider);
    if (server == null) return;
    try {
      final channel = await wsConnect(
        server,
        '/ws/follow',
        query: {'path': widget.path},
      );
      if (!mounted) {
        await channel.sink.close();
        return;
      }
      _channel = channel;
      _subscription = channel.stream.listen(
        _onWsData,
        onError: (Object error) {
          if (!mounted) return;
          _stopFollow();
          setState(() {});
          showErrorSnack(context, error);
        },
        onDone: () {
          if (!mounted) return;
          _stopFollow();
          setState(() {});
        },
      );
      setState(() => _following = true);
      showSuccessSnack(context, '已开启实时跟踪');
    } on WsAuthException catch (e) {
      if (!mounted) return;
      await _showWsAuthDialog(e.message);
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    }
  }

  void _stopFollow() {
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    _pending = '';
    _following = false;
  }

  void _onWsData(dynamic data) {
    String text;
    if (data is String) {
      text = data;
    } else if (data is List<int>) {
      text = utf8.decode(data, allowMalformed: true);
    } else {
      return;
    }
    final combined = _pending + stripAnsi(text);
    final parts = combined.split('\n');
    _pending = parts.removeLast();
    if (parts.isEmpty) return;
    final atBottom = _isAtBottom();
    setState(() {
      _lines = [..._lines, ...parts.map((e) => e.replaceAll('\r', ''))];
      // 避免长时间跟踪导致内存无限增长。
      if (_lines.length > 5000) {
        _lines = _lines.sublist(_lines.length - 5000);
      }
    });
    if (atBottom) _scrollToBottom();
  }

  bool _isAtBottom() {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    return position.pixels >= position.maxScrollExtent - 80;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  Future<void> _showWsAuthDialog(String message) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('无法开启实时跟踪'),
        content: Text(
          '$message\n\n'
          '实时日志走面板会话认证，需要在「服务器配置」中补充面板登录用户名与密码。',
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

  Future<void> _clear() async {
    final ok = await showConfirmDialog(
      context,
      title: '清空日志',
      content: '确定要清空该任务的日志文件吗？此操作不可恢复。',
      confirmText: '清空',
      danger: true,
    );
    if (!ok) return;
    try {
      await ref.read(cronRepoProvider).truncateFile(widget.path);
      if (!mounted) return;
      setState(() {
        _lines = [];
        _tailLoaded = 0;
        _hasMore = false;
      });
      showSuccessSnack(context, '日志已清空');
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _copyAll() async {
    await Clipboard.setData(ClipboardData(text: _lines.join('\n')));
    if (mounted) showSuccessSnack(context, '日志已复制到剪贴板');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final server = ref.watch(activeServerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('任务日志'),
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
            tooltip: _following ? '停止实时跟踪日志' : '开启实时跟踪日志',
            icon: Icon(_following ? Icons.pause_circle : Icons.play_circle),
            color: _following ? theme.colorScheme.primary : null,
            onPressed: server == null ? null : _toggleFollow,
          ),
          A11yIconButton(
            tooltip: '重新读取日志',
            icon: const Icon(Icons.refresh),
            onPressed: server == null || _loading ? null : _reload,
          ),
          PopupMenuButton<String>(
            tooltip: '更多日志操作',
            onSelected: (value) {
              if (value == 'copy') _copyAll();
              if (value == 'clear') _clear();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'copy', child: Text('复制全部')),
              PopupMenuItem(
                value: 'clear',
                child: Text(
                  '清空日志',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ],
          ),
        ],
      ),
      body: server == null
          ? const NoServerView()
          : _loading
          ? const LoadingView(message: '正在读取日志…')
          : _error != null
          ? ErrorView(error: _error!, onRetry: _reload)
          : _buildContent(theme),
    );
  }

  Widget _buildContent(ThemeData theme) {
    if (_lines.isEmpty) {
      return RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 80),
              child: Center(
                child: Text(
                  '日志为空',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (_following)
          Container(
            width: double.infinity,
            color: theme.colorScheme.primaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text(
              '实时跟踪中…',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _reload,
            child: SelectionArea(
              child: ListView.builder(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                itemCount: _lines.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    if (!_hasMore) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Center(
                          child: Text(
                            '已到日志开头',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ),
                      );
                    }
                    return Center(
                      child: _loadingMore
                          ? const Padding(
                              padding: EdgeInsets.all(8),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : TextButton(
                              onPressed: _loadEarlier,
                              child: const Text('加载更早的日志'),
                            ),
                    );
                  }
                  final line = _lines[index - 1];
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
        ),
      ],
    );
  }
}
