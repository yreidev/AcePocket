import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/format.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../models/container_volume.dart';
import '../models/json_utils.dart';
import '../providers/container_providers.dart';
import '../widgets/action_runner.dart';
import '../widgets/paged_list_view.dart';
import '../widgets/status_badge.dart';
import '../widgets/volume_create_sheet.dart';

/// 存储卷管理页（`/containers/volume`）。
class VolumeListPage extends ConsumerWidget {
  const VolumeListPage({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final ok = await showVolumeCreateSheet(context);
    if (ok) {
      await ref.read(containerVolumesProvider.notifier).reload();
    }
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    ContainerVolume volume,
  ) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除存储卷',
      content:
          '确定要删除「${volume.name}」吗？\n卷内数据将被永久删除，此操作不可恢复。'
          '${volume.inUse ? '\n该卷正被 ${volume.refCount} 个容器使用，删除可能失败。' : ''}',
      confirmText: '删除',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    final success = await runAction(
      context,
      pending: '正在删除存储卷…',
      success: '存储卷已删除',
      action: () => ref.read(containerRepoProvider).removeVolume(volume.name),
    );
    if (success) {
      await ref.read(containerVolumesProvider.notifier).reload();
    }
  }

  Future<void> _prune(BuildContext context, WidgetRef ref) async {
    final ok = await showConfirmDialog(
      context,
      title: '清理存储卷',
      content: '将删除所有未被任何容器使用的存储卷，卷内数据一并丢失。确定继续吗？',
      confirmText: '清理',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    final success = await runAction(
      context,
      pending: '正在清理未使用的存储卷…',
      success: '清理完成',
      action: () => ref.read(containerRepoProvider).pruneVolumes(),
    );
    if (success) {
      await ref.read(containerVolumesProvider.notifier).reload();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(containerVolumesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('存储卷管理'),
        actions: [
          A11yIconButton(
            tooltip: '刷新存储卷列表',
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.read(containerVolumesProvider.notifier).reload(),
          ),
          A11yIconButton(
            tooltip: '清理未使用的存储卷',
            icon: const Icon(Icons.cleaning_services_outlined),
            onPressed: () => _prune(context, ref),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('创建存储卷'),
      ),
      body: PagedListView<ContainerVolume>(
        state: state,
        loadingMessage: '正在加载存储卷列表…',
        emptyMessage: '还没有任何存储卷',
        emptyIcon: Icons.storage_outlined,
        emptyAction: FilledButton.icon(
          onPressed: () => _create(context, ref),
          icon: const Icon(Icons.add),
          label: const Text('创建存储卷'),
        ),
        onRefresh: () => ref.read(containerVolumesProvider.notifier).refresh(),
        onLoadMore: () =>
            ref.read(containerVolumesProvider.notifier).loadMore(),
        onRetry: () => ref.invalidate(containerVolumesProvider),
        itemBuilder: (context, volume, _) => _VolumeTile(
          volume: volume,
          onDelete: () => _remove(context, ref, volume),
        ),
      ),
    );
  }
}

class _VolumeTile extends StatelessWidget {
  const _VolumeTile({required this.volume, required this.onDelete});

  final ContainerVolume volume;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        volume.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          StatusBadge(
                            label: volume.driver.isEmpty
                                ? 'local'
                                : volume.driver,
                            tone: BadgeTone.info,
                            dense: true,
                          ),
                          if (volume.scope.isNotEmpty)
                            StatusBadge(
                              label: '作用域 ${volume.scope}',
                              tone: BadgeTone.neutral,
                              dense: true,
                            ),
                          if (volume.size.isNotEmpty)
                            StatusBadge(
                              label: volume.size,
                              tone: BadgeTone.neutral,
                              dense: true,
                            ),
                          StatusBadge(
                            label: volume.inUse
                                ? '${volume.refCount} 个容器使用中'
                                : '未使用',
                            tone: volume.inUse
                                ? BadgeTone.success
                                : BadgeTone.neutral,
                            dense: true,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                A11yIconButton(
                  tooltip: '删除存储卷 ${volume.name}',
                  icon: Icon(
                    Icons.delete_outline,
                    color: theme.colorScheme.error,
                  ),
                  onPressed: onDelete,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              volume.mountPoint.isEmpty ? '-' : volume.mountPoint,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFamily: 'monospace',
                fontFamilyFallback: const ['Courier'],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.schedule,
                  size: 13,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    formatDateTime(volume.createdAt),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
