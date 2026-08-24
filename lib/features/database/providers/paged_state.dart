import '../../../core/providers/paged_notifier_base.dart';
import '../models/page_data.dart';

export '../../../core/providers/paged_notifier_base.dart' show PagedState;

/// 列表页默认每页条数。
const int kDatabasePageSize = 20;

/// 分页取数函数：给定页码与每页条数，返回该页数据。
typedef PageFetcher<T> = Future<PageData<T>> Function(int page, int limit);

/// 数据库模块分页 Notifier 基类（带 family 参数）。
///
/// 并发控制（请求代次 / 在途标志 / loadMoreError）由
/// [PagedFamilyAsyncNotifier] 统一提供；子类只需提供 [fetcher]。
///
/// 注意：面板的 `GET /api/database` 实现为 `database[(page-1)*limit:]`
/// （见 `internal/biz/database.go` 的 `List`），会把偏移之后的**全部**条目返回，
/// 因此这里统一按 limit 截断，保证各接口的分页语义一致。
abstract class DatabasePagedNotifier<T, Arg>
    extends PagedFamilyAsyncNotifier<T, Arg> {
  DatabasePagedNotifier(super.arg);

  /// 拉取指定页数据，由子类提供。
  PageFetcher<T> get fetcher;

  @override
  int get pageSize => kDatabasePageSize;

  @override
  Future<PagedResult<T>> fetchPage(int page, int limit) async {
    final data = await fetcher(page, limit);
    return PagedResult(items: _truncate(data.items, limit), total: data.total);
  }

  /// 重新加载第一页（下拉刷新 / 增删改之后调用）；失败时进入错误态。
  Future<void> refresh() => reloadFirstPage(toErrorState: true);
}

List<T> _truncate<T>(List<T> items, int limit) =>
    items.length > limit ? items.sublist(0, limit) : items;
