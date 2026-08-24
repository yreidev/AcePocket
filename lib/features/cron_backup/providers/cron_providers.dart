import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/server_store.dart';
import '../models/cron.dart';
import '../models/page_result.dart';
import '../repo/cron_repo.dart';
import 'paged_state.dart';

/// 计划任务仓库（跟随当前选中的服务器变化）。
final cronRepoProvider = Provider<CronRepo>((ref) {
  return CronRepo(ref.watch(apiClientProvider));
});

/// 每页条数。
const kCronPageSize = 20;

/// 计划任务列表（分页 + 下拉刷新）。
final cronListProvider =
    AsyncNotifierProvider.autoDispose<CronListNotifier, PagedState<Cron>>(
      CronListNotifier.new,
    );

class CronListNotifier extends CronBackupPagedNotifier<Cron> {
  @override
  int get pageSize => kCronPageSize;

  @override
  Future<PagedState<Cron>> build() {
    // watch 而非 read：切换服务器时 repo 重建，列表需随之重新加载
    // （基类的 buildFirstPage 会让在途请求过期，旧服务器的响应不会写回）。
    ref.watch(cronRepoProvider);
    return super.build();
  }

  @override
  Future<PageResult<Cron>> fetch(int page, int limit) =>
      ref.read(cronRepoProvider).list(page: page, limit: limit);

  /// 启用 / 停用任务（成功后就地更新列表项）。
  Future<void> setStatus(Cron cron, bool status) async {
    await ref.read(cronRepoProvider).setStatus(cron.id, status);
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        items: current.items
            .map((e) => e.id == cron.id ? e.copyWith(status: status) : e)
            .toList(),
      ),
    );
  }

  /// 删除任务（成功后从列表移除）。
  Future<void> delete(int id) async {
    await ref.read(cronRepoProvider).delete(id);
    final current = state.value;
    if (current == null) return;
    final items = current.items.where((e) => e.id != id).toList();
    state = AsyncData(
      current.copyWith(
        items: items,
        total: current.total > 0 ? current.total - 1 : 0,
      ),
    );
  }
}
