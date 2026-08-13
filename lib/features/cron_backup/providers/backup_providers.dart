import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/storage/server_store.dart';
import '../models/backup_file.dart';
import '../models/page_result.dart';
import '../repo/backup_repo.dart';
import '../repo/backup_transfer.dart';
import 'options_providers.dart';
import 'paged_state.dart';

/// 备份仓库（跟随当前选中的服务器变化）。
final backupRepoProvider = Provider<BackupRepo>((ref) {
  return BackupRepo(ref.watch(apiClientProvider));
});

/// 备份上传客户端（流式 multipart，见 [BackupUploader]）。
///
/// 下载复用 files 模块的 `panelTransferClientProvider`
/// （[PanelTransferClient.downloadBackup] 本身即流式），
/// 上传因备份接口没有分片入口、整体读入会 OOM，另用流式实现。
final backupUploaderProvider = Provider<BackupUploader>((ref) {
  final server = ref.watch(activeServerProvider);
  if (server == null) {
    throw const ApiException('尚未选择服务器，请先在「服务器」中添加并选中一台服务器');
  }
  return BackupUploader(server);
});

/// 每页条数。
const kBackupPageSize = 20;

/// 备份文件列表（按类型分页）。
final backupListProvider = AsyncNotifierProvider.autoDispose
    .family<BackupListNotifier, PagedState<BackupFile>, String>(
      BackupListNotifier.new,
    );

class BackupListNotifier
    extends CronBackupPagedFamilyNotifier<BackupFile, String> {
  @override
  int get pageSize => kBackupPageSize;

  @override
  Future<PagedState<BackupFile>> build(String arg) {
    // watch 而非 read：切换服务器时 repo 重建，列表需随之重新加载。
    ref.watch(backupRepoProvider);
    return super.build(arg);
  }

  @override
  Future<PageResult<BackupFile>> fetch(int page, int limit) =>
      ref.read(backupRepoProvider).list(type: arg, page: page, limit: limit);

  /// 删除备份文件（成功后从列表移除）。
  Future<void> delete(BackupFile file) async {
    await ref.read(backupRepoProvider).delete(type: arg, file: file.name);
    final current = state.valueOrNull;
    if (current == null) return;
    final items = current.items.where((e) => e.name != file.name).toList();
    state = AsyncData(
      current.copyWith(
        items: items,
        total: current.total > 0 ? current.total - 1 : 0,
      ),
    );
  }
}

/// 备份页可展示的类型标签（按面板已安装的环境过滤）。
///
/// 检测失败时退回展示全部类型，保证功能可用。
final backupTypeTabsProvider = FutureProvider.autoDispose<List<String>>((
  ref,
) async {
  const fallback = BackupTypes.listable;
  try {
    final dbTypes = await ref.watch(installedDatabaseTypesProvider.future);
    final redis = await ref.watch(appInstalledProvider('redis').future);
    final valkey = await ref.watch(appInstalledProvider('valkey').future);
    final tabs = <String>[BackupTypes.website];
    for (final t in BackupTypes.databaseTypes) {
      if (dbTypes.contains(t)) tabs.add(t);
    }
    if (redis) tabs.add(BackupTypes.redis);
    if (valkey) tabs.add(BackupTypes.valkey);
    tabs.add(BackupTypes.panel);
    tabs.add(BackupTypes.path);
    return tabs;
  } catch (_) {
    return fallback;
  }
});
