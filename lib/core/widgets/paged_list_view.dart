import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_exception.dart';
import '../providers/paged_notifier_base.dart';
import 'app_snack.dart';
import 'empty_view.dart';
import 'error_view.dart';
import 'fade_switch.dart';
import 'loading_view.dart';

/// 各模块统一的分页列表：下拉刷新 + 触底加载更多 + 空态 / 错误态。
///
/// 数据来自继承 core `PagedAsyncNotifier` 的 provider，[state] 直接传
/// `ref.watch(...)`。上一页失败后不再自动重试，避免滚动触发请求风暴。
class PagedListView<T> extends StatefulWidget {
  const PagedListView({
    super.key,
    required this.state,
    required this.onRefresh,
    required this.onLoadMore,
    required this.onRetry,
    required this.itemBuilder,
    this.header,
    this.emptyMessage = '暂无数据',
    this.emptyIcon = Icons.inbox_outlined,
    this.emptyAction,
    this.emptyView,
    this.loadingMessage,
    this.padding = const EdgeInsets.fromLTRB(0, 4, 0, 96),
    this.totalLabel,
  });

  final AsyncValue<PagedState<T>> state;

  /// 下拉刷新。未捕获的异常会以错误 SnackBar 展示。
  final Future<void> Function() onRefresh;

  /// 触底 / 点击「加载更多」。Notifier 内部有在途去重。
  final VoidCallback onLoadMore;

  /// 首屏失败后的重试。
  final VoidCallback onRetry;

  final Widget Function(BuildContext context, T item, int index) itemBuilder;

  /// 列表顶部内容（随列表滚动），空态时同样展示。
  final Widget? header;

  final String emptyMessage;
  final IconData emptyIcon;
  final Widget? emptyAction;

  /// 自定义空态；提供时忽略 [emptyMessage] / [emptyIcon] / [emptyAction]。
  final Widget? emptyView;

  final String? loadingMessage;
  final EdgeInsetsGeometry padding;

  /// 全部加载完毕时的底部文案；默认「共 n 条」。
  final String Function(int total)? totalLabel;

  @override
  State<PagedListView<T>> createState() => _PagedListViewState<T>();
}

class _PagedListViewState<T> extends State<PagedListView<T>> {
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
    if (widget.state.value?.loadMoreError != null) return;
    final position = _controller.position;
    if (position.pixels >= position.maxScrollExtent - 240) {
      widget.onLoadMore();
    }
  }

  Future<void> _handleRefresh() async {
    try {
      await widget.onRefresh();
    } catch (error) {
      if (!mounted) return;
      showErrorSnack(context, '刷新失败：${describeError(error)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 四种占位态之间交叉淡入，避免请求返回瞬间整页硬闪。
    // key 按「态」而不是按数据取值：同一态内翻页 / 局部增删只更新列表本身，
    // 不会把 ListView 整个换掉（那会丢滚动位置并重跑一次淡入）。
    return FadeSwitch(expand: true, child: _buildBody(context));
  }

  Widget _buildBody(BuildContext context) {
    final state = widget.state;
    // 切服务器等依赖变化会带 previous 变成 AsyncLoading：hasValue 仍为 true，
    // 但条目属于旧依赖，必须盖住。下拉刷新是 isRefreshing（仍为 AsyncData），
    // 继续展示当前列表，由 RefreshIndicator 负责转圈。
    if (!state.isReloading && !state.hasValue && state.hasError) {
      return ErrorView(
        key: const ValueKey<String>('paged-error'),
        error: state.error!,
        onRetry: widget.onRetry,
      );
    }
    if (state.isReloading || !state.hasValue) {
      return LoadingView(
        key: const ValueKey<String>('paged-loading'),
        message: widget.loadingMessage,
      );
    }

    final paged = state.requireValue;
    final items = paged.items;

    if (items.isEmpty) {
      return RefreshIndicator(
        key: const ValueKey<String>('paged-empty'),
        onRefresh: _handleRefresh,
        child: LayoutBuilder(
          // 空态没有下一页可加载，因此不挂 _controller：交叉淡入期间新旧内容
          // 同时在树上，同一个 ScrollController 被两个可滚动组件持有会直接抛错。
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.header != null) widget.header!,
                  SizedBox(
                    height: constraints.maxHeight * 0.6,
                    child:
                        widget.emptyView ??
                        EmptyView(
                          message: widget.emptyMessage,
                          icon: widget.emptyIcon,
                          action: widget.emptyAction,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final headerCount = widget.header == null ? 0 : 1;
    return RefreshIndicator(
      key: const ValueKey<String>('paged-list'),
      onRefresh: _handleRefresh,
      child: ListView.builder(
        controller: _controller,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: widget.padding,
        itemCount: items.length + headerCount + 1,
        itemBuilder: (context, index) {
          if (headerCount == 1 && index == 0) return widget.header!;
          final itemIndex = index - headerCount;
          if (itemIndex < items.length) {
            return widget.itemBuilder(context, items[itemIndex], itemIndex);
          }
          return _Footer(
            loading: paged.loadingMore,
            hasMore: paged.hasMore,
            total: paged.total,
            error: paged.loadMoreError,
            totalLabel: widget.totalLabel ?? ((total) => '共 $total 条'),
            onLoadMore: widget.onLoadMore,
          );
        },
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.loading,
    required this.hasMore,
    required this.total,
    required this.error,
    required this.totalLabel,
    required this.onLoadMore,
  });

  final bool loading;
  final bool hasMore;
  final int total;
  final Object? error;
  final String Function(int total) totalLabel;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!loading && error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          children: [
            Text(
              '加载下一页失败：${describeError(error!)}',
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onLoadMore,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }
    final Widget child;
    if (loading) {
      child = const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (hasMore) {
      child = TextButton(onPressed: onLoadMore, child: const Text('加载更多'));
    } else {
      child = Text(
        totalLabel(total),
        textAlign: TextAlign.center,
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
