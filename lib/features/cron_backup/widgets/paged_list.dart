import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/paged_notifier_base.dart';
import '../../../core/widgets/paged_list_view.dart';

/// 计划任务 / 备份列表：外层已经处理 loading / error，这里直接喂 [PagedState]。
class PagedList<T> extends StatelessWidget {
  const PagedList({
    super.key,
    required this.state,
    required this.onRefresh,
    required this.onLoadMore,
    required this.itemBuilder,
    required this.emptyView,
    this.header,
    this.padding = const EdgeInsets.only(top: 8, bottom: 96),
  });

  final PagedState<T> state;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLoadMore;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final Widget emptyView;
  final Widget? header;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return PagedListView<T>(
      state: AsyncData(state),
      onRefresh: onRefresh,
      onLoadMore: () {
        onLoadMore();
      },
      onRetry: () {
        onLoadMore();
      },
      itemBuilder: itemBuilder,
      emptyView: emptyView,
      header: header,
      padding: padding,
    );
  }
}
