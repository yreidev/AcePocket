import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/storage/server_store.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../models/backup_storage.dart';
import '../providers/storage_providers.dart';
import '../widgets/feedback.dart';
import '../widgets/no_server_view.dart';
import '../widgets/paged_list.dart';
import '../widgets/storage_tile.dart';

/// 备份存储列表页（`/backups/storages`）。
class BackupStoragePage extends ConsumerStatefulWidget {
  const BackupStoragePage({super.key});

  @override
  ConsumerState<BackupStoragePage> createState() => _BackupStoragePageState();
}

class _BackupStoragePageState extends ConsumerState<BackupStoragePage> {
  @override
  Widget build(BuildContext context) {
    final server = ref.watch(activeServerProvider);
    final state = ref.watch(backupStorageListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('备份存储')),
      floatingActionButton: server == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: const Text('添加存储'),
            ),
      body: server == null
          ? const NoServerView()
          : state.when(
              loading: () => const LoadingView(message: '正在加载备份存储…'),
              error: (error, _) => ErrorView(
                error: error,
                onRetry: () => ref.invalidate(backupStorageListProvider),
              ),
              data: (data) => PagedList<BackupStorage>(
                state: data,
                onRefresh: () =>
                    ref.read(backupStorageListProvider.notifier).refresh(),
                onLoadMore: _loadMore,
                emptyView: EmptyView(
                  icon: Icons.cloud_off_outlined,
                  message: '还没有备份存储',
                  action: FilledButton.icon(
                    onPressed: _create,
                    icon: const Icon(Icons.add),
                    label: const Text('添加存储'),
                  ),
                ),
                itemBuilder: (context, storage, _) => StorageTile(
                  storage: storage,
                  onEdit: () => _edit(storage),
                  onDelete: () => _delete(storage),
                ),
              ),
            ),
    );
  }

  /// 加载下一页；失败由 [PagedList] 在列表底部展示并重试，不再弹 SnackBar。
  Future<void> _loadMore() =>
      ref.read(backupStorageListProvider.notifier).loadMore();

  Future<void> _create() async {
    final saved = await context.push<bool>('/backups/storages/edit');
    if (saved == true) {
      await ref.read(backupStorageListProvider.notifier).refresh();
      ref.invalidate(storageOptionsProvider);
    }
  }

  Future<void> _edit(BackupStorage storage) async {
    if (storage.isLocal) {
      showInfoSnack(context, '本地存储由面板设置维护，不可在此编辑');
      return;
    }
    final saved = await context.push<bool>(
      '/backups/storages/edit?id=${storage.id}',
    );
    if (saved == true) {
      await ref.read(backupStorageListProvider.notifier).refresh();
      ref.invalidate(storageOptionsProvider);
    }
  }

  Future<void> _delete(BackupStorage storage) async {
    if (storage.isLocal) return;
    final ok = await showConfirmDialog(
      context,
      title: '删除备份存储',
      content:
          '确定要删除「${storage.name}」吗？'
          '使用该存储的计划任务将无法继续上传备份。',
      confirmText: '删除',
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(backupStorageListProvider.notifier).delete(storage.id);
      ref.invalidate(storageOptionsProvider);
      if (mounted) showSuccessSnack(context, '已删除');
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }
}
