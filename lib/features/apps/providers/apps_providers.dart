import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/server_store.dart';
import '../models/app_category.dart';
import '../models/app_custom.dart';
import '../models/app_item.dart';
import '../models/paged.dart';
import '../repo/apps_repo.dart';

/// 每页条数。
const int kAppPageSize = 20;

/// 应用商店仓库；未选择服务器时为 null。
final appsRepoProvider = Provider<AppsRepo?>((ref) {
  final server = ref.watch(activeServerProvider);
  if (server == null) return null;
  return AppsRepo(ref.watch(apiClientProvider));
});

/// 应用分类列表。
final appCategoriesProvider = FutureProvider.autoDispose<List<AppCategory>>((
  ref,
) async {
  final repo = ref.watch(appsRepoProvider);
  if (repo == null) return const <AppCategory>[];
  return repo.categories();
});

/// 应用列表筛选条件（分类 + 关键词，两个标签页共用）。
class AppFilter {
  const AppFilter({this.category = '', this.keyword = ''});

  /// 分类 slug，空表示全部分类。
  final String category;

  /// 搜索关键词。
  final String keyword;

  AppFilter copyWith({String? category, String? keyword}) => AppFilter(
    category: category ?? this.category,
    keyword: keyword ?? this.keyword,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppFilter &&
          other.category == category &&
          other.keyword == keyword;

  @override
  int get hashCode => Object.hash(category, keyword);
}

final appFilterProvider = NotifierProvider<AppFilterNotifier, AppFilter>(
  AppFilterNotifier.new,
);

class AppFilterNotifier extends Notifier<AppFilter> {
  @override
  AppFilter build() => const AppFilter();

  void setCategory(String category) {
    if (state.category == category) return;
    state = state.copyWith(category: category);
  }

  void setKeyword(String keyword) {
    if (state.keyword == keyword) return;
    state = state.copyWith(keyword: keyword);
  }

  void reset() => state = const AppFilter();
}

typedef AppListState = PagedListState<AppItem>;

/// 应用列表（family 参数：true = 仅已安装，false = 全部应用）。
///
/// 筛选条件或当前服务器变化时自动重新加载第一页。
final appListProvider = NotifierProvider.autoDispose
    .family<AppListNotifier, AppListState, bool>(AppListNotifier.new);

class AppListNotifier extends Notifier<AppListState> {
  AppListNotifier(this._installedOnly);

  final bool _installedOnly;

  AppsRepo? _repo;
  AppFilter _filter = const AppFilter();
  bool _alive = true;

  /// 请求代次：依赖变化 / 手动刷新时自增，用于丢弃过期请求的结果。
  int _generation = 0;

  @override
  AppListState build() {
    _alive = true;
    ref.onDispose(() => _alive = false);

    _repo = ref.watch(appsRepoProvider);
    _filter = ref.watch(appFilterProvider);

    if (_repo == null) {
      return AppListState(isLoading: false, error: '尚未选择服务器，请先在服务器列表中选择一台面板');
    }

    final generation = ++_generation;
    Future.microtask(() => _loadFirstPage(generation));
    return AppListState(isLoading: true);
  }

  /// 下拉刷新 / 错误重试；失败时返回错误对象供页面提示（成功返回 null）。
  ///
  /// 刷新失败**不会清空已加载的数据**：整页替换成错误页会一并丢掉滚动位置与
  /// 已展开的条目，而下拉刷新失败大多只是一次网络抖动。仅在列表本来就为空
  /// （首屏）时才写入 `state.error` 让页面展示错误页。
  Future<Object?> refresh() async {
    if (_repo == null) return null;
    final generation = ++_generation;
    return _loadFirstPage(generation, silent: true);
  }

  /// 错误页「重试」：先展示首屏加载态再重新拉取，让点击有即时反馈。
  Future<Object?> reload() async {
    if (_repo == null) return null;
    return _loadFirstPage(++_generation);
  }

  Future<Object?> _loadFirstPage(int generation, {bool silent = false}) async {
    final repo = _repo;
    if (repo == null || _stale(generation)) return null;
    if (!silent) {
      _set(generation, state.copyWith(isLoading: true, clearError: true));
    }
    try {
      final paged = await repo.list(
        page: 1,
        limit: kAppPageSize,
        category: _filter.category,
        query: _filter.keyword,
        installedOnly: _installedOnly,
      );
      _set(
        generation,
        AppListState(
          items: paged.items,
          total: paged.total,
          page: 1,
          isLoading: false,
        ),
      );
      return null;
    } catch (e) {
      if (_stale(generation)) return null;
      if (state.items.isNotEmpty) {
        // 已有数据：保留列表与滚动位置，错误交由调用方以提示条展示。
        _set(
          generation,
          state.copyWith(
            isLoading: false,
            isLoadingMore: false,
            clearError: true,
          ),
        );
      } else {
        _set(generation, AppListState(isLoading: false, error: e));
      }
      return e;
    }
  }

  /// 加载下一页；失败时返回错误对象供页面提示（成功返回 null）。
  Future<Object?> loadMore() async {
    final repo = _repo;
    if (repo == null) return null;
    final current = state;
    if (current.isLoading || current.isLoadingMore || !current.hasMore) {
      return null;
    }
    final generation = _generation;
    _set(generation, current.copyWith(isLoadingMore: true));
    try {
      final next = current.page + 1;
      final paged = await repo.list(
        page: next,
        limit: kAppPageSize,
        category: _filter.category,
        query: _filter.keyword,
        installedOnly: _installedOnly,
      );
      if (_stale(generation)) return null;
      final merged = [...state.items, ...paged.items];
      _set(
        generation,
        state.copyWith(
          items: merged,
          // 空页即视为到底，避免 total 与实际条数不一致时反复触发「加载更多」。
          total: paged.items.isEmpty ? merged.length : paged.total,
          page: next,
          isLoadingMore: false,
        ),
      );
      return null;
    } catch (e) {
      _set(generation, state.copyWith(isLoadingMore: false));
      return e;
    }
  }

  /// 本地更新某个应用（如切换首页显示开关后即时反馈）。
  void patch(String slug, AppItem Function(AppItem item) update) {
    final items = state.items
        .map((item) => item.slug == slug ? update(item) : item)
        .toList();
    _set(_generation, state.copyWith(items: items));
  }

  bool _stale(int generation) => !_alive || generation != _generation;

  void _set(int generation, AppListState next) {
    if (_stale(generation)) return;
    state = next;
  }
}

/// 应用自定义编译参数（仅 `custom_supported` 为 true 的应用可用）。
final appCustomProvider = FutureProvider.autoDispose.family<AppCustom, String>((
  ref,
  slug,
) async {
  final repo = ref.watch(appsRepoProvider);
  if (repo == null) return const AppCustom();
  return repo.getCustom(slug);
});

/// 刷新两个标签页的应用列表（安装 / 卸载 / 更新后调用）。
void refreshAllAppLists(WidgetRef ref) {
  ref.read(appListProvider(true).notifier).refresh();
  ref.read(appListProvider(false).notifier).refresh();
}
