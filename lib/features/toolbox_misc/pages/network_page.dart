import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/version/panel_feature.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/feature_gate.dart';
import '../../../core/widgets/loading_view.dart';
import '../models/network_models.dart';
import '../providers/toolbox_misc_providers.dart';
import '../widgets/network_filter_sheet.dart';
import '../widgets/toolbox_tiles.dart';

/// 网络信息页：系统当前的 TCP / UDP 连接（含监听端口）。
///
/// 接口见 `internal/route/toolbox_network.go`（GET `/toolbox_network/list`），
/// 支持状态 / PID / 进程名 / 端口过滤与排序，服务端内存分页。
class NetworkPage extends ConsumerStatefulWidget {
  const NetworkPage({super.key});

  @override
  ConsumerState<NetworkPage> createState() => _NetworkPageState();
}

class _NetworkPageState extends ConsumerState<NetworkPage> {
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    // 上次加载更多失败时不再自动触发，避免停在列表底部反复重试；
    // 由底部的「重试」按钮显式重发。
    final paged = ref.read(networkConnectionsProvider).valueOrNull;
    if (paged == null || paged.loadMoreError != null) return;
    final position = _controller.position;
    if (position.pixels >= position.maxScrollExtent - 240) {
      ref.read(networkConnectionsProvider.notifier).loadMore();
    }
  }

  Future<void> _refresh() async {
    try {
      await ref.read(networkConnectionsProvider.notifier).refresh();
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    }
  }

  Future<void> _openFilter() async {
    final current = ref.read(networkFilterProvider);
    final result = await showNetworkFilterSheet(context, filter: current);
    if (result == null || result == current) return;
    ref.read(networkFilterProvider.notifier).state = result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filter = ref.watch(networkFilterProvider);
    final state = ref.watch(networkConnectionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('网络信息'),
        actions: [
          A11yIconButton(
            tooltip: '筛选与排序连接列表',
            icon: Badge(
              isLabelVisible: filter.activeCount > 0,
              label: Text('${filter.activeCount}'),
              child: const Icon(Icons.filter_list),
            ),
            onPressed: _openFilter,
          ),
          A11yIconButton(
            tooltip: '刷新连接列表',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(networkConnectionsProvider),
          ),
        ],
      ),
      body: Column(
        children: [
          const FeatureUnsupportedBanner(feature: PanelFeature.toolboxNetwork),
          _filterBar(filter),
          Expanded(child: _body(state, theme)),
        ],
      ),
    );
  }

  Widget _filterBar(NetworkFilter filter) {
    final theme = Theme.of(context);
    final chips = <Widget>[
      for (final state in filter.states)
        _removableChip(state, () {
          final next = {...filter.states}..remove(state);
          ref.read(networkFilterProvider.notifier).state = filter.copyWith(
            states: next,
          );
        }),
      if (filter.process.isNotEmpty)
        _removableChip('进程 ${filter.process}', () {
          ref.read(networkFilterProvider.notifier).state = filter.copyWith(
            process: '',
          );
        }),
      if (filter.pid.isNotEmpty)
        _removableChip('PID ${filter.pid}', () {
          ref.read(networkFilterProvider.notifier).state = filter.copyWith(
            pid: '',
          );
        }),
      if (filter.port.isNotEmpty)
        _removableChip('端口 ${filter.port}', () {
          ref.read(networkFilterProvider.notifier).state = filter.copyWith(
            port: '',
          );
        }),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      color: theme.colorScheme.surfaceContainerLow,
      child: Row(
        children: [
          Expanded(
            child: chips.isEmpty
                ? Text(
                    '按 ${kNetworkSortFields[filter.sort] ?? filter.sort}'
                    '${filter.order == 'asc' ? '升序' : '降序'}排列',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                : Wrap(spacing: 6, runSpacing: 6, children: chips),
          ),
          if (chips.isNotEmpty)
            TextButton(
              onPressed: () => ref.read(networkFilterProvider.notifier).state =
                  const NetworkFilter(),
              child: const Text('清空'),
            ),
        ],
      ),
    );
  }

  Widget _removableChip(String label, VoidCallback onDeleted) {
    return InputChip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      onDeleted: onDeleted,
    );
  }

  Widget _body(
    AsyncValue<PagedState<NetworkConnection>> state,
    ThemeData theme,
  ) {
    if (!state.hasValue) {
      if (state.hasError) {
        return ErrorView(
          error: state.error!,
          onRetry: () => ref.invalidate(networkConnectionsProvider),
        );
      }
      return const LoadingView(message: '读取网络连接…');
    }

    final paged = state.requireValue;
    if (paged.items.isEmpty) {
      // 空态区分「筛选后无结果」与「本来就没有连接」，前者给出清空筛选入口。
      final hasFilter = ref.read(networkFilterProvider).activeCount > 0;
      return RefreshIndicator(
        onRefresh: _refresh,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: EmptyView(
                message: hasFilter
                    ? '没有符合筛选条件的连接，试试放宽或清空筛选条件'
                    : '当前没有 TCP / UDP 连接记录，下拉可重新读取',
                icon: Icons.lan_outlined,
                action: hasFilter
                    ? OutlinedButton.icon(
                        onPressed: () =>
                            ref.read(networkFilterProvider.notifier).state =
                                const NetworkFilter(),
                        icon: const Icon(Icons.filter_alt_off_outlined),
                        label: const Text('清空筛选条件'),
                      )
                    : null,
              ),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        controller: _controller,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        itemCount: paged.items.length + 1,
        itemBuilder: (context, index) {
          if (index == paged.items.length) {
            return _footer(paged, theme);
          }
          return _connectionTile(paged.items[index], theme);
        },
      ),
    );
  }

  Widget _connectionTile(NetworkConnection conn, ThemeData theme) {
    final stateColor = switch (conn.state) {
      'LISTEN' => theme.colorScheme.primary,
      'ESTABLISHED' => theme.colorScheme.secondary,
      'NONE' => theme.colorScheme.outline,
      _ => theme.colorScheme.tertiary,
    };

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onLongPress: () => _copy(conn),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  TagChip(
                    label: conn.type.toUpperCase(),
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  TagChip(label: conn.state, color: stateColor),
                  const Spacer(),
                  Text(
                    conn.pid > 0 ? 'PID ${conn.pid}' : '无进程信息',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                conn.process.isEmpty ? '未知进程' : conn.process,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              _addressRow('本地', conn.local, theme),
              if (conn.hasRemote) _addressRow('远程', conn.remote, theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addressRow(String label, String value, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _copy(NetworkConnection conn) {
    final text =
        '${conn.type.toUpperCase()} ${conn.state}\n'
        '进程：${conn.process.isEmpty ? '未知' : conn.process}（PID ${conn.pid}）\n'
        '本地：${conn.local}\n远程：${conn.remote}';
    Clipboard.setData(ClipboardData(text: text));
    showSuccessSnack(context, '连接信息已复制');
  }

  Widget _footer(PagedState<NetworkConnection> paged, ThemeData theme) {
    final Widget child;
    if (paged.loadingMore) {
      child = const BusyIndicator();
    } else if (paged.loadMoreError != null) {
      // 加载更多失败：基建把错误记在 loadMoreError 里，这里展示并提供重试。
      child = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '加载更多失败：${describeError(paged.loadMoreError!)}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: () =>
                ref.read(networkConnectionsProvider.notifier).loadMore(),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('重试'),
          ),
        ],
      );
    } else if (paged.hasMore) {
      child = TextButton(
        onPressed: () =>
            ref.read(networkConnectionsProvider.notifier).loadMore(),
        child: const Text('加载更多'),
      );
    } else {
      child = Text(
        '共 ${paged.total} 条连接',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(child: child),
    );
  }
}
