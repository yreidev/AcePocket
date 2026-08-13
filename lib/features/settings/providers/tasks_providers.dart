import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/server_store.dart';
import '../models/file_tail.dart';
import '../models/page_result.dart';
import '../models/task_item.dart';
import '../repo/task_repo.dart';
import 'paged_notifier.dart';

/// 后台任务数据仓库。
final taskRepoProvider = Provider<TaskRepository>(
  (ref) => TaskRepository(ref.watch(apiClientProvider)),
);

/// 是否存在运行中的任务（任务中心顶部提示）。
final taskRunningProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(taskRepoProvider).hasRunningTask(),
);

/// 任务分页列表。
class TaskListNotifier extends PagedNotifier<TaskItem> {
  @override
  Future<PagedState<TaskItem>> build() {
    // 建立依赖：切换服务器（apiClientProvider 变化）时自动重建列表。
    ref.watch(taskRepoProvider);
    return super.build();
  }

  @override
  Future<PageResult<TaskItem>> fetch(int page, int limit) =>
      ref.read(taskRepoProvider).list(page: page, limit: limit);
}

final taskListProvider =
    AsyncNotifierProvider.autoDispose<TaskListNotifier, PagedState<TaskItem>>(
        TaskListNotifier.new);

/// 单个任务详情。
final taskDetailProvider =
    FutureProvider.autoDispose.family<TaskItem, int>((ref, id) {
  return ref.watch(taskRepoProvider).get(id);
});

/// 任务日志（读取任务 `log` 字段指向的日志文件尾部）。
///
/// 参数为日志文件路径；路径为空时直接返回空结果。
final taskLogProvider =
    FutureProvider.autoDispose.family<FileTailResult, String>((ref, path) {
  if (path.isEmpty) return Future.value(const FileTailResult());
  return ref.watch(taskRepoProvider).tailLog(path, limit: 1000);
});
