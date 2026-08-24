import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/server_store.dart';
import '../models/backup_storage.dart';
import '../models/option_item.dart';
import '../models/page_result.dart';
import '../repo/backup_storage_repo.dart';
import 'paged_state.dart';

/// 备份存储仓库（跟随当前选中的服务器变化）。
final backupStorageRepoProvider = Provider<BackupStorageRepo>((ref) {
  return BackupStorageRepo(ref.watch(apiClientProvider));
});

/// 每页条数。
const kStoragePageSize = 20;

/// 备份存储列表（分页）。
final backupStorageListProvider =
    AsyncNotifierProvider.autoDispose<
      BackupStorageListNotifier,
      PagedState<BackupStorage>
    >(BackupStorageListNotifier.new);

class BackupStorageListNotifier extends CronBackupPagedNotifier<BackupStorage> {
  @override
  int get pageSize => kStoragePageSize;

  @override
  Future<PagedState<BackupStorage>> build() {
    // watch 而非 read：切换服务器时 repo 重建，列表需随之重新加载。
    ref.watch(backupStorageRepoProvider);
    return super.build();
  }

  @override
  Future<PageResult<BackupStorage>> fetch(int page, int limit) =>
      ref.read(backupStorageRepoProvider).list(page: page, limit: limit);

  /// 删除备份存储（成功后从列表移除）。
  Future<void> delete(int id) async {
    await ref.read(backupStorageRepoProvider).delete(id);
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

/// 备份存储下拉选项（创建备份 / 备份类计划任务时选择目标存储）。
final storageOptionsProvider = FutureProvider.autoDispose<List<StorageOption>>((
  ref,
) async {
  final result = await ref
      .watch(backupStorageRepoProvider)
      .list(page: 1, limit: 1000);
  final options = result.items
      .map((e) => StorageOption(id: e.id, name: e.name))
      .toList();
  if (!options.any((e) => e.id == 0)) {
    options.insert(0, const StorageOption(id: 0, name: '本地存储'));
  }
  return options;
});
