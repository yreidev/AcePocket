import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../models/log_entry.dart';
import '../providers/logs_providers.dart';
import '../widgets/log_tile.dart';

/// 面板日志查看（`/api/log/*`）。
///
/// 面板日志接口不支持分页，只支持「取最近 N 条」（服务端上限 1000 条），
/// 因此这里以「加载更多」逐步提升条数上限，并提供归档日期切换。
class LogsPage extends StatelessWidget {
  const LogsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('面板日志'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: '操作日志'),
              Tab(text: '数据库'),
              Tab(text: 'HTTP'),
              Tab(text: 'SSH 登录'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _PanelLogView(type: 'app'),
            _PanelLogView(type: 'db'),
            _PanelLogView(type: 'http'),
            _SshLogView(),
          ],
        ),
      ),
    );
  }
}

/// 列表底部：条数说明 + 「加载更多」/ 加载中 / 加载失败重试。
///
/// 因为「加载更多」实际是换一个更大的 limit 重新请求整段日志，失败或加载中都
/// 只影响这一小块，已显示的内容与滚动位置保持不动。
class _LogFooter extends StatelessWidget {
  const _LogFooter({
    required this.count,
    required this.limit,
    required this.maxLimit,
    required this.loading,
    required this.error,
    required this.onLoadMore,
    required this.onRetry,
  });

  final int count;
  final int limit;
  final int maxLimit;
  final bool loading;
  final Object? error;
  final VoidCallback onLoadMore;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final captionStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    if (loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(height: 8),
            Text('正在加载日志…', style: captionStyle),
          ],
        ),
      );
    }

    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          children: [
            Text(
              '日志加载失败：${describeError(error!)}',
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    final canLoadMore = limit < maxLimit && count >= limit;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Column(
        children: [
          Text(
            canLoadMore
                ? '已显示最近 $count 条（上限 $limit 条）'
                : '已显示全部 $count 条'
                      '${limit >= maxLimit ? '（已达面板上限 $maxLimit 条）' : ''}',
            textAlign: TextAlign.center,
            style: captionStyle,
          ),
          if (canLoadMore) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onLoadMore,
              icon: const Icon(Icons.expand_more),
              label: const Text('加载更多'),
            ),
          ],
        ],
      ),
    );
  }
}

/// 面板文件日志（app / db / http）。
class _PanelLogView extends ConsumerStatefulWidget {
  const _PanelLogView({required this.type});

  final String type;

  @override
  ConsumerState<_PanelLogView> createState() => _PanelLogViewState();
}

class _PanelLogViewState extends ConsumerState<_PanelLogView>
    with AutomaticKeepAliveClientMixin {
  static const int _maxLimit = 1000;
  static const int _step = 200;

  String _date = '';
  int _limit = 200;

  /// 最近一次成功加载的日志。
  ///
  /// 「加载更多」= 换一个更大的 limit 重新请求（family 键变化 → 全新加载），
  /// 若直接按 provider 的 loading 态渲染，整页会闪回加载骨架并把用户滚动位置
  /// 重置到顶部。这里保留上一批数据继续渲染，只在列表底部展示加载状态。
  List<LogEntry>? _loaded;

  @override
  bool get wantKeepAlive => true;

  LogQuery get _query =>
      LogQuery(type: widget.type, date: _date, limit: _limit);

  void _reload() {
    ref.invalidate(logDatesProvider(widget.type));
    ref.invalidate(logListProvider(_query));
  }

  Future<void> _refresh() async {
    _reload();
    try {
      await ref.read(logListProvider(_query).future);
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final datesAsync = ref.watch(logDatesProvider(widget.type));
    final logsAsync = ref.watch(logListProvider(_query));

    // 有新数据就更新缓存；仍在加载 / 出错时沿用上一批，列表与滚动位置不动。
    final fresh = logsAsync.value;
    if (fresh != null) _loaded = fresh;
    final entries = fresh ?? _loaded;

    final dateItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: '', child: Text('今天')),
      ...(datesAsync.value ?? const <String>[]).map(
        (d) => DropdownMenuItem(value: d, child: Text(d)),
      ),
    ];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: dateItems.any((e) => e.value == _date)
                      ? _date
                      : '',
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '日期'),
                  items: dateItems,
                  onChanged: (v) {
                    if (v == null || v == _date) return;
                    setState(() {
                      _date = v;
                      _limit = 200;
                      // 换日期是另一段内容，旧缓存不能再复用。
                      _loaded = null;
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              A11yIconButton(
                tooltip: '刷新日志列表',
                icon: const Icon(Icons.refresh),
                style: IconButton.styleFrom(
                  backgroundColor: theme.colorScheme.secondaryContainer,
                  foregroundColor: theme.colorScheme.onSecondaryContainer,
                ),
                onPressed: _reload,
              ),
            ],
          ),
        ),
        Expanded(
          child: entries == null
              ? (logsAsync.hasError
                    ? ErrorView(
                        error: logsAsync.error!,
                        onRetry: () => ref.invalidate(logListProvider(_query)),
                      )
                    : const LoadingView(message: '正在加载日志…'))
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: entries.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: MediaQuery.sizeOf(context).height * 0.5,
                              child: const EmptyView(
                                message: '该日期没有日志记录',
                                icon: Icons.description_outlined,
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(top: 4, bottom: 24),
                          itemCount: entries.length + 1,
                          itemBuilder: (context, index) {
                            if (index == entries.length) {
                              return _LogFooter(
                                count: entries.length,
                                limit: _limit,
                                maxLimit: _maxLimit,
                                loading: logsAsync.isLoading,
                                error: logsAsync.error,
                                onLoadMore: () => setState(() {
                                  _limit = (_limit + _step).clamp(
                                    _step,
                                    _maxLimit,
                                  );
                                }),
                                onRetry: () =>
                                    ref.invalidate(logListProvider(_query)),
                              );
                            }
                            return LogEntryTile(entry: entries[index]);
                          },
                        ),
                ),
        ),
      ],
    );
  }
}

/// SSH 登录日志。
class _SshLogView extends ConsumerStatefulWidget {
  const _SshLogView();

  @override
  ConsumerState<_SshLogView> createState() => _SshLogViewState();
}

class _SshLogViewState extends ConsumerState<_SshLogView>
    with AutomaticKeepAliveClientMixin {
  static const int _maxLimit = 1000;
  static const int _step = 200;

  int _limit = 200;

  /// 同 [_PanelLogViewState._loaded]：提升条数上限时保留已显示内容。
  List<SshLoginLog>? _loaded;

  @override
  bool get wantKeepAlive => true;

  Future<void> _refresh() async {
    ref.invalidate(sshLogProvider(_limit));
    try {
      await ref.read(sshLogProvider(_limit).future);
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final logsAsync = ref.watch(sshLogProvider(_limit));

    final fresh = logsAsync.value;
    if (fresh != null) _loaded = fresh;
    final logs = fresh ?? _loaded;

    if (logs == null) {
      return logsAsync.hasError
          ? ErrorView(
              error: logsAsync.error!,
              onRetry: () => ref.invalidate(sshLogProvider(_limit)),
            )
          : const LoadingView(message: '正在读取 SSH 登录日志…');
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: logs.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.6,
                  child: const EmptyView(
                    message: '暂无 SSH 登录记录',
                    icon: Icons.vpn_key_outlined,
                  ),
                ),
              ],
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              itemCount: logs.length + 1,
              itemBuilder: (context, index) {
                if (index == logs.length) {
                  return _LogFooter(
                    count: logs.length,
                    limit: _limit,
                    maxLimit: _maxLimit,
                    loading: logsAsync.isLoading,
                    error: logsAsync.error,
                    onLoadMore: () => setState(() {
                      _limit = (_limit + _step).clamp(_step, _maxLimit);
                    }),
                    onRetry: () => ref.invalidate(sshLogProvider(_limit)),
                  );
                }
                return SshLogTile(log: logs[index]);
              },
            ),
    );
  }
}
