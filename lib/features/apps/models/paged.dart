library;

export '../../../core/models/paged.dart';

class PagedListState<T> {
  PagedListState({
    List<T>? items,
    this.total = 0,
    this.page = 1,
    this.isLoading = true,
    this.isLoadingMore = false,
    this.error,
  }) : items = items ?? <T>[];

  /// 已加载的全部条目。
  final List<T> items;

  /// 服务端返回的总条数。
  final int total;

  /// 已加载到的页码。
  final int page;

  /// 首屏加载中。
  final bool isLoading;

  /// 加载下一页中。
  final bool isLoadingMore;

  /// 首屏加载错误（加载更多失败不写入此字段，由页面以提示条展示）。
  final Object? error;

  /// 是否还有更多数据。
  bool get hasMore => items.length < total;

  /// 首屏加载完成且无数据。
  bool get isEmpty => !isLoading && error == null && items.isEmpty;

  PagedListState<T> copyWith({
    List<T>? items,
    int? total,
    int? page,
    bool? isLoading,
    bool? isLoadingMore,
    Object? error,
    bool clearError = false,
  }) {
    return PagedListState<T>(
      items: items ?? this.items,
      total: total ?? this.total,
      page: page ?? this.page,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: clearError ? null : (error ?? this.error),
    );
  }
}
