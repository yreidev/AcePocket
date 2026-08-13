import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/storage/server_store.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/task_snack.dart';
import '../../files/providers/files_providers.dart';
import '../../files/repo/transfer_client.dart';
import '../../files/widgets/download_dialogs.dart';
import '../models/backup_file.dart';
import '../providers/backup_providers.dart';
import '../repo/backup_transfer.dart';
import '../widgets/backup_dialogs.dart';
import '../widgets/backup_file_tile.dart';
import '../widgets/backup_transfer_dialogs.dart';
import '../widgets/feedback.dart';
import '../widgets/no_server_view.dart';
import '../widgets/paged_list.dart';

/// 备份管理页（`/backups`）。
///
/// 按类型分标签展示本地备份文件，支持创建备份、恢复、删除与查看下载信息。
class BackupListPage extends ConsumerStatefulWidget {
  const BackupListPage({super.key});

  @override
  ConsumerState<BackupListPage> createState() => _BackupListPageState();
}

class _BackupListPageState extends ConsumerState<BackupListPage> {
  String _type = BackupTypes.website;

  /// 正在提交创建 / 恢复请求，期间禁用入口避免重复下发同一个后台任务。
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    final server = ref.watch(activeServerProvider);
    final tabs = ref.watch(backupTypeTabsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('备份管理'),
        actions: [
          if (server != null)
            A11yIconButton(
              tooltip: '上传备份文件',
              icon: const Icon(Icons.upload_file_outlined),
              onPressed: _submitting ? null : () => _upload(_type),
            ),
          A11yIconButton(
            tooltip: '管理备份存储',
            icon: const Icon(Icons.cloud_outlined),
            onPressed: () => context.push('/backups/storages'),
          ),
        ],
      ),
      floatingActionButton: server == null || !BackupTypes.canCreate(_type)
          ? null
          : FloatingActionButton.extended(
              onPressed: _submitting ? null : _create,
              icon: const Icon(Icons.add),
              label: const Text('创建备份'),
            ),
      body: server == null
          ? const NoServerView()
          : tabs.when(
              loading: () => const LoadingView(message: '正在加载备份类型…'),
              error: (error, _) => ErrorView(
                error: error,
                onRetry: () => ref.invalidate(backupTypeTabsProvider),
              ),
              data: (types) {
                final available = types.isEmpty ? BackupTypes.listable : types;
                final current =
                    available.contains(_type) ? _type : available.first;
                if (current != _type) {
                  // 当前类型不在可用列表中时回退到第一个。
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _type = current);
                  });
                }
                return Column(
                  children: [
                    _TypeTabs(
                      types: available,
                      selected: current,
                      onSelected: (value) => setState(() => _type = value),
                    ),
                    const Divider(height: 1),
                    Expanded(child: _buildList(current)),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildList(String type) {
    final state = ref.watch(backupListProvider(type));
    return state.when(
      loading: () => const LoadingView(message: '正在加载备份列表…'),
      error: (error, _) => ErrorView(
        error: error,
        onRetry: () => ref.invalidate(backupListProvider(type)),
      ),
      data: (data) => PagedList<BackupFile>(
        state: data,
        onRefresh: () => ref.read(backupListProvider(type).notifier).refresh(),
        onLoadMore: () => _loadMore(type),
        header: _Notice(type: type),
        emptyView: EmptyView(
          icon: Icons.inventory_2_outlined,
          message: '暂无${BackupTypes.label(type)}备份',
          action: BackupTypes.canCreate(type)
              ? FilledButton.icon(
                  onPressed: _submitting ? null : _create,
                  icon: const Icon(Icons.add),
                  label: const Text('创建备份'),
                )
              : null,
        ),
        itemBuilder: (context, file, _) => BackupFileTile(
          file: file,
          onInfo: () => _showInfo(file, type),
          onDownload: () => _download(file, type),
          onRestore:
              BackupTypes.canRestore(type) ? () => _restore(file, type) : null,
          onDelete:
              BackupTypes.canManage(type) ? () => _delete(file, type) : null,
        ),
      ),
    );
  }

  /// 加载下一页；失败由 [PagedList] 在列表底部展示并重试，不再弹 SnackBar。
  Future<void> _loadMore(String type) =>
      ref.read(backupListProvider(type).notifier).loadMore();

  Future<void> _showInfo(BackupFile file, String type) async {
    final server = ref.read(activeServerProvider);
    await showBackupInfoDialog(
      context,
      file: file,
      type: type,
      baseUrl: server?.normalizedBaseUrl ?? '',
      onDownload: () => _download(file, type),
    );
  }

  /// 下载备份到本机（`GET /backup/{type}/download`）。
  ///
  /// 保存目录、进度对话框与「打开 / 复制路径」复用 files 模块的通用实现。
  Future<void> _download(BackupFile file, String type) async {
    final PanelTransferClient transfer;
    try {
      transfer = ref.read(panelTransferClientProvider);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
      return;
    }
    if (!mounted) return;

    final outcome = await showDownloadProgressDialog(
      context,
      fileName: file.name,
      runner: ({
        required savePath,
        required onProgress,
        required cancelToken,
      }) =>
          transfer.downloadBackup(
        type: type,
        fileName: file.name,
        savePath: savePath,
        onProgress: onProgress,
        cancelToken: cancelToken,
      ),
    );
    if (!mounted || outcome == null) return;
    if (outcome.cancelled) {
      showInfoSnack(context, '下载已取消');
      return;
    }
    final error = outcome.error;
    if (error != null) {
      showErrorSnack(context, error);
      return;
    }
    final saved = outcome.file;
    if (saved == null) return;
    await showDownloadResultDialog(context, file: saved);
  }

  /// 从本机选择文件上传为备份（`POST /backup/{type}/upload`）。
  Future<void> _upload(String type) async {
    if (_submitting) return;
    final BackupUploader uploader;
    try {
      uploader = ref.read(backupUploaderProvider);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
      return;
    }
    if (!mounted) return;

    FilePickerResult? picked;
    try {
      picked = await FilePicker.pickFiles(
        // 备份包可能有数 GB，不预读进内存，交由流式上传按需读取。
        withData: false,
        withReadStream: false,
      );
    } catch (e) {
      if (mounted) showErrorSnack(context, '打开文件选择器失败：$e');
      return;
    }
    if (picked == null || picked.files.isEmpty || !mounted) return;

    final choice = picked.files.first;
    final path = choice.path;
    if (path == null || path.isEmpty) {
      showErrorSnack(context, '无法读取所选文件，请换一个位置重试');
      return;
    }
    final name = choice.name.isEmpty ? path.split('/').last : choice.name;
    if (!BackupUploader.isUploadable(name)) {
      showErrorSnack(
        context,
        '面板只接受 ${BackupUploader.kUploadAllowedExtensions.join('、')} 格式的备份文件',
      );
      return;
    }

    final ok = await showConfirmDialog(
      context,
      title: '上传备份文件',
      content: '将「$name」上传到「${BackupTypes.label(type)}」备份目录。\n'
          '目录下已存在同名文件时面板会拒绝上传。',
      confirmText: '开始上传',
    );
    if (!ok || !mounted) return;

    final outcome = await showBackupUploadDialog(
      context,
      uploader: uploader,
      type: type,
      source: File(path),
      fileName: name,
    );
    if (!mounted || outcome == null) return;
    if (outcome.cancelled) {
      showInfoSnack(context, '上传已取消');
      return;
    }
    final error = outcome.error;
    if (error != null) {
      showErrorSnack(context, error);
      return;
    }
    showSuccessSnack(context, '上传成功');
    // refresh 内部已把失败转成整页错误态，不会抛出。
    await ref.read(backupListProvider(type).notifier).refresh();
  }

  Future<void> _create() async {
    if (_submitting) return;
    final type = _type;
    final result = await showCreateBackupDialog(context, type: type);
    if (result == null || !mounted) return;
    setState(() => _submitting = true);
    try {
      await ref.read(backupRepoProvider).create(
            type: type,
            target: result.target,
            storage: result.storage,
          );
      if (!mounted) return;
      showTaskSubmittedSnack(context, '备份任务已提交');
      await ref.read(backupListProvider(type).notifier).refresh();
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _restore(BackupFile file, String type) async {
    if (_submitting) return;
    final target = await showRestoreTargetDialog(
      context,
      type: type,
      file: file,
    );
    if (target == null || !mounted) return;
    setState(() => _submitting = true);
    try {
      await ref.read(backupRepoProvider).restore(
            type: type,
            file: file.path,
            target: target,
          );
      if (mounted) showTaskSubmittedSnack(context, '恢复任务已提交');
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _delete(BackupFile file, String type) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除备份',
      content: '确定要删除「${file.name}」吗？此操作不可恢复。',
      confirmText: '删除',
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(backupListProvider(type).notifier).delete(file);
      if (mounted) showSuccessSnack(context, '已删除');
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }
}

class _TypeTabs extends StatelessWidget {
  const _TypeTabs({
    required this.types,
    required this.selected,
    required this.onSelected,
  });

  final List<String> types;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: types.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final type = types[index];
          return ChoiceChip(
            label: Text(BackupTypes.label(type)),
            selected: type == selected,
            onSelected: (_) => onSelected(type),
          );
        },
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final messages = <String>[
      '此处仅展示本地存储中的备份，远程备份请在对应的备份存储中查看。',
      '可下载备份到本机，也可用右上角的「上传备份文件」把本机文件导入备份目录。',
      if (type == BackupTypes.path) '目录备份不支持在此恢复或删除，请在文件管理中操作。',
      if (type == BackupTypes.panel) '面板自身的备份不提供恢复入口，请在面板端操作。',
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline,
              size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              messages.join('\n'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
