import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../providers/website_stat_providers.dart';

/// 统计分页列表通用外壳：下拉刷新 + 滚动到底自动加载下一页 + 错误重试。
///
/// 由调用方 watch 具体的 provider 并把 [state] 与回调传进来，
/// 从而复用于 URI / IP / 慢请求 / 错误日志等分页统计。
class PagedStatList<T> extends StatefulWidget {
  const PagedStatList({
    super.key,
    required this.state,
    required this.onRefresh,
    required this.onLoadMore,
    required this.itemBuilder,
    this.emptyMessage = '所选时间范围内暂无数据',
    this.header,
  });

  final AsyncValue<StatPagedState<T>> state;
  final Future<void> Function() onRefresh;
  final VoidCallback onLoadMore;

  /// 单行构建器（index 为数据下标，不含 header）。
  final Widget Function(BuildContext context, T item, int index) itemBuilder;

  final String emptyMessage;

  /// 列表顶部的固定内容（如筛选器）。
  final Widget? header;

  @override
  State<PagedStatList<T>> createState() => _PagedStatListState<T>();
}

class _PagedStatListState<T> extends State<PagedStatList<T>> {
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
    final position = _controller.position;
    if (position.pixels >= position.maxScrollExtent - 240) {
      widget.onLoadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return widget.state.when(
      loading: () => const LoadingView(message: '正在加载统计数据…'),
      error: (error, _) => ErrorView(error: error, onRetry: widget.onRefresh),
      data: (state) {
        if (state.items.isEmpty) {
          return RefreshIndicator(
            onRefresh: widget.onRefresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (widget.header != null) widget.header!,
                SizedBox(height: MediaQuery.of(context).size.height * 0.15),
                EmptyView(
                  message: widget.emptyMessage,
                  icon: Icons.query_stats_outlined,
                ),
              ],
            ),
          );
        }

        final headerCount = widget.header == null ? 0 : 1;
        return RefreshIndicator(
          onRefresh: widget.onRefresh,
          child: ListView.builder(
            controller: _controller,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 32),
            itemCount: state.items.length + headerCount + 1,
            itemBuilder: (context, index) {
              if (headerCount == 1 && index == 0) return widget.header!;
              final dataIndex = index - headerCount;
              if (dataIndex == state.items.length) {
                if (state.loadMoreError != null) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      children: [
                        Text(
                          '加载更多失败：'
                          '${describeError(state.loadMoreError!)}',
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: widget.onLoadMore,
                          icon: const Icon(Icons.refresh),
                          label: const Text('重新加载'),
                        ),
                      ],
                    ),
                  );
                }
                if (state.loadingMore) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      state.hasMore ? '上拉加载更多' : '共 ${state.total} 条',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              }
              return widget.itemBuilder(
                context,
                state.items[dataIndex],
                dataIndex,
              );
            },
          ),
        );
      },
    );
  }
}
