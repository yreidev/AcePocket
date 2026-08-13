import '../../../core/providers/paged_notifier_base.dart';
import '../models/page_result.dart';

export '../../../core/providers/paged_notifier_base.dart' show PagedState;

/// 本模块分页取数函数：给定页码（从 1 开始）与每页条数，返回该页数据。
typedef CronBackupFetcher<T> =
    Future<PageResult<T>> Function(int page, int limit);

/// 计划任务与备份模块的分页 Notifier 基类（无 family 参数）。
///
/// 并发控制（请求代次 / 在途标志 / loadMoreError）全部由
/// [PagedAsyncNotifier] 提供，见 `core/providers/paged_notifier_base.dart`；
/// 子类只需实现 [fetch]，并在 `build()` 里 `ref.watch` 对应 repo provider
/// 后调用 `super.build()`。
abstract class CronBackupPagedNotifier<T> extends PagedAsyncNotifier<T> {
  /// 拉取第 [page] 页（页码从 1 开始），由子类实现。
  Future<PageResult<T>> fetch(int page, int limit);

  @override
  Future<PagedResult<T>> fetchPage(int page, int limit) async {
    final result = await fetch(page, limit);
    return PagedResult(items: result.items, total: result.total);
  }

  /// 下拉刷新 / 增删改后重载第一页；失败时进入整页错误态（由 ErrorView 重试）。
  Future<void> refresh() => reloadFirstPage(toErrorState: true);
}

/// 计划任务与备份模块的分页 Notifier 基类（带 family 参数，如按备份类型分页）。
abstract class CronBackupPagedFamilyNotifier<T, Arg>
    extends PagedFamilyAsyncNotifier<T, Arg> {
  /// 拉取第 [page] 页（页码从 1 开始），由子类实现。
  Future<PageResult<T>> fetch(int page, int limit);

  @override
  Future<PagedResult<T>> fetchPage(int page, int limit) async {
    final result = await fetch(page, limit);
    return PagedResult(items: result.items, total: result.total);
  }

  /// 下拉刷新 / 增删改后重载第一页；失败时进入整页错误态。
  Future<void> refresh() => reloadFirstPage(toErrorState: true);
}
