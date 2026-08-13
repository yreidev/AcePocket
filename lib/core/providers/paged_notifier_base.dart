import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 通用分页基础设施：请求代次（generation）+ 在途标志，
/// 解决「refresh 与 loadMore 交错」时过期响应写回 state 导致的
/// 列表弹回旧数据 / 条目重复 / 已删除条目复活等竞态问题。
///
/// 参考实现见 apps 模块（`apps_providers.dart` 的 [_generation] 模式），
/// 本文件将其抽象为可复用的 [PagedPager] 与三种 Notifier 基类。

/// 单页数据（items + total）。
///
/// 各模块的分页响应模型（`Paged` / `PageResult` / `PageData`）字段一致，
/// 由各自的 Notifier 基类适配为本类型。
class PagedResult<T> {
  const PagedResult({required this.items, required this.total});

  final List<T> items;
  final int total;
}

/// 分页列表的 UI 状态。
class PagedState<T> {
  const PagedState({
    required this.items,
    required this.total,
    required this.page,
    required this.hasMore,
    this.loadingMore = false,
    this.loadMoreError,
  });

  /// 已加载的全部条目（逐页累加）。
  final List<T> items;

  /// 服务端返回的总条数（空页收尾时会修正为已加载条数）。
  final int total;

  /// 已加载到的页码（从 1 开始）。
  final int page;

  /// 是否还有下一页。
  final bool hasMore;

  /// 是否正在加载下一页。
  final bool loadingMore;

  /// 加载下一页失败时的错误（在列表底部展示「加载失败，点击重试」）。
  final Object? loadMoreError;

  bool get isEmpty => items.isEmpty;

  PagedState<T> copyWith({
    List<T>? items,
    int? total,
    int? page,
    bool? hasMore,
    bool? loadingMore,
    Object? loadMoreError,
    bool clearLoadMoreError = false,
  }) {
    return PagedState<T>(
      items: items ?? this.items,
      total: total ?? this.total,
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
      loadingMore: loadingMore ?? this.loadingMore,
      loadMoreError: clearLoadMoreError
          ? null
          : (loadMoreError ?? this.loadMoreError),
    );
  }
}

/// 分页取数函数：给定页码（从 1 开始）与每页条数，返回该页数据。
typedef PagedFetcher<T> = Future<PagedResult<T>> Function(int page, int limit);

/// 分页请求的并发控制核心（与 Riverpod 解耦，便于单元测试）。
///
/// - 每次「重新加载第一页」（build 重跑 / 下拉刷新）自增 [_generation]，
///   await 返回后用 [isStale] 校验，过期响应一律丢弃、不写入 state；
/// - loadMore 的在途标志存放在本对象字段而非 state 里，
///   refresh 重建 state 时不会误清标志导致并发发起第二个 loadMore。
class PagedPager<T> {
  PagedPager({this.pageSize = 20});

  /// 每页条数。
  final int pageSize;

  /// 请求代次：重新加载第一页时自增，用于丢弃过期请求的结果。
  int _generation = 0;

  /// 是否有在途的 loadMore 请求（跨代次保持，直到该请求结束）。
  bool _loadMoreInFlight = false;

  /// [generation] 对应的请求是否已过期。
  bool isStale(int generation) => generation != _generation;

  /// 供 Notifier 的 build() 使用：使所有在途请求过期并拉取第一页
  /// （首屏错误由 Riverpod 捕获为 AsyncError）。
  Future<PagedState<T>> buildFirstPage(PagedFetcher<T> fetch) {
    _generation++;
    return _fetchFirstPage(fetch);
  }

  /// 重新拉取第一页（下拉刷新 / 增删改后的重载），并使在途请求全部过期。
  ///
  /// [toErrorState] 为 true 时失败进入整页错误态（ErrorView 展示并可重试）；
  /// 为 false 时保留现有数据并把异常抛给调用方（SnackBar 提示）。
  Future<void> reloadFirstPage({
    required PagedFetcher<T> fetch,
    required void Function(AsyncValue<PagedState<T>> value) write,
    required bool toErrorState,
  }) async {
    final generation = ++_generation;
    if (toErrorState) {
      final value = await AsyncValue.guard(() => _fetchFirstPage(fetch));
      if (isStale(generation)) return;
      write(value);
    } else {
      // 失败时异常向上抛出，state 保持不动。
      final next = await _fetchFirstPage(fetch);
      if (isStale(generation)) return;
      write(AsyncData(next));
    }
  }

  /// 加载下一页并追加。
  ///
  /// - 已在加载中 / 没有更多数据时为空操作；
  /// - await 返回后校验代次，refresh / 重建期间在途的响应直接丢弃；
  /// - 失败时把错误记录到 [PagedState.loadMoreError]，由列表底部展示并重试。
  Future<void> loadMore({
    required AsyncValue<PagedState<T>> Function() read,
    required void Function(AsyncValue<PagedState<T>> value) write,
    required PagedFetcher<T> fetch,
  }) async {
    final current = read().valueOrNull;
    if (current == null ||
        _loadMoreInFlight ||
        current.loadingMore ||
        !current.hasMore) {
      return;
    }
    final generation = _generation;
    _loadMoreInFlight = true;
    write(
      AsyncData(current.copyWith(loadingMore: true, clearLoadMoreError: true)),
    );
    try {
      final nextPage = current.page + 1;
      final result = await fetch(nextPage, pageSize);
      if (isStale(generation)) return;
      // 用写入时刻的最新 state 合并，保留期间发生的本地增删（patch / removeItem）。
      final base = read().valueOrNull ?? current;
      final merged = [...base.items, ...result.items];
      // 空页即视为到底：以已加载条数收尾，避免 total 与实际条数不一致
      // （如筛选后 total 未变化、搜索接口对 page > 1 返回空页）时
      // 「加载更多」被反复触发。
      final total = result.items.isEmpty ? merged.length : result.total;
      write(
        AsyncData(
          PagedState<T>(
            items: merged,
            total: total,
            page: nextPage,
            // 返回不足一页即视为到底（与 website 模块既有语义一致）。
            hasMore: result.items.length >= pageSize && merged.length < total,
          ),
        ),
      );
    } catch (error) {
      if (isStale(generation)) return;
      final base = read().valueOrNull ?? current;
      write(AsyncData(base.copyWith(loadingMore: false, loadMoreError: error)));
    } finally {
      _loadMoreInFlight = false;
    }
  }

  Future<PagedState<T>> _fetchFirstPage(PagedFetcher<T> fetch) async {
    final result = await fetch(1, pageSize);
    return PagedState<T>(
      items: result.items,
      total: result.total,
      page: 1,
      hasMore:
          result.items.length >= pageSize && result.items.length < result.total,
    );
  }
}

/// 三种 Notifier 基类共享的分页行为。
///
/// 子类实现 [fetchPage]；`build()` 中照常 `ref.watch` 依赖后调用
/// `super.build()`（内部走 [buildFirstPage]，会使在途请求过期）。
mixin PagedNotifierMixin<T> {
  /// 由 AsyncNotifier 基类提供。
  AsyncValue<PagedState<T>> get state;
  set state(AsyncValue<PagedState<T>> value);

  /// 每页条数，子类可覆写。
  int get pageSize => 20;

  /// 并发控制器；随 Notifier 实例存活（Riverpod 重建 build 时实例不变）。
  late final PagedPager<T> pager = PagedPager<T>(pageSize: pageSize);

  /// 拉取第 [page] 页数据（页码从 1 开始），由子类实现。
  Future<PagedResult<T>> fetchPage(int page, int limit);

  /// 首屏 / 依赖变化重建：使在途请求过期并拉取第一页。
  Future<PagedState<T>> buildFirstPage() => pager.buildFirstPage(fetchPage);

  /// 重新拉取第一页；各模块以此实现自己的 refresh / reload 语义
  /// （[toErrorState] 含义见 [PagedPager.reloadFirstPage]）。
  Future<void> reloadFirstPage({required bool toErrorState}) =>
      pager.reloadFirstPage(
        fetch: fetchPage,
        write: (value) => state = value,
        toErrorState: toErrorState,
      );

  /// 上拉加载下一页（代次校验 + 在途去重 + loadMoreError 记录）。
  Future<void> loadMore() => pager.loadMore(
    read: () => state,
    write: (value) => state = value,
    fetch: fetchPage,
  );
}

/// 分页 Notifier 基类（autoDispose，无 family 参数）。
abstract class PagedAsyncNotifier<T>
    extends AutoDisposeAsyncNotifier<PagedState<T>>
    with PagedNotifierMixin<T> {
  @override
  Future<PagedState<T>> build() => buildFirstPage();
}

/// 分页 Notifier 基类（autoDispose + family 参数）。
abstract class PagedFamilyAsyncNotifier<T, Arg>
    extends AutoDisposeFamilyAsyncNotifier<PagedState<T>, Arg>
    with PagedNotifierMixin<T> {
  @override
  Future<PagedState<T>> build(Arg arg) => buildFirstPage();
}

/// 分页 Notifier 基类（常驻，不随页面销毁，如网站列表）。
abstract class KeepAlivePagedAsyncNotifier<T>
    extends AsyncNotifier<PagedState<T>>
    with PagedNotifierMixin<T> {
  @override
  Future<PagedState<T>> build() => buildFirstPage();
}
