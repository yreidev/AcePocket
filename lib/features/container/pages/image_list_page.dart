import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/format.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../models/container_image.dart';
import '../models/json_utils.dart';
import '../providers/container_providers.dart';
import '../widgets/action_runner.dart';
import '../widgets/image_pull_sheet.dart';
import '../widgets/info_row.dart';
import '../widgets/paged_list_view.dart';
import '../widgets/status_badge.dart';

/// 镜像管理页（`/containers/image`）。
class ImageListPage extends ConsumerWidget {
  const ImageListPage({super.key});

  Future<void> _pull(BuildContext context, WidgetRef ref) async {
    final ok = await showImagePullSheet(context);
    if (ok) {
      await ref.read(containerImagesProvider.notifier).reload();
    }
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    ContainerImage image,
  ) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除镜像',
      content:
          '确定要删除镜像「${image.displayName}」吗？此操作不可恢复。'
          '${image.inUse ? '\n该镜像仍被 ${image.containers} 个容器使用，删除可能失败。' : ''}',
      confirmText: '删除',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    final success = await runAction(
      context,
      pending: '正在删除镜像…',
      success: '镜像已删除',
      action: () => ref.read(containerRepoProvider).removeImage(image.id),
    );
    if (success) {
      await ref.read(containerImagesProvider.notifier).reload();
    }
  }

  Future<void> _prune(BuildContext context, WidgetRef ref) async {
    final ok = await showConfirmDialog(
      context,
      title: '清理镜像',
      content: '将删除所有未被任何容器使用的镜像，此操作不可恢复。确定继续吗？',
      confirmText: '清理',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    final success = await runAction(
      context,
      pending: '正在清理未使用的镜像…',
      success: '清理完成',
      action: () => ref.read(containerRepoProvider).pruneImages(),
    );
    if (success) {
      await ref.read(containerImagesProvider.notifier).reload();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(containerImagesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('镜像管理'),
        actions: [
          A11yIconButton(
            tooltip: '刷新镜像列表',
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.read(containerImagesProvider.notifier).reload(),
          ),
          A11yIconButton(
            tooltip: '清理未使用的镜像',
            icon: const Icon(Icons.cleaning_services_outlined),
            onPressed: () => _prune(context, ref),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _pull(context, ref),
        icon: const Icon(Icons.download_outlined),
        label: const Text('拉取镜像'),
      ),
      body: PagedListView<ContainerImage>(
        state: state,
        loadingMessage: '正在加载镜像列表…',
        emptyMessage: '还没有任何镜像',
        emptyIcon: Icons.album_outlined,
        emptyAction: FilledButton.icon(
          onPressed: () => _pull(context, ref),
          icon: const Icon(Icons.download_outlined),
          label: const Text('拉取镜像'),
        ),
        onRefresh: () => ref.read(containerImagesProvider.notifier).refresh(),
        onLoadMore: () => ref.read(containerImagesProvider.notifier).loadMore(),
        onRetry: () => ref.invalidate(containerImagesProvider),
        itemBuilder: (context, image, _) => _ImageTile(
          image: image,
          onDelete: () => _remove(context, ref, image),
        ),
      ),
    );
  }
}

class _ImageTile extends StatelessWidget {
  const _ImageTile({required this.image, required this.onDelete});

  final ContainerImage image;
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
                        image.displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      // 用 Wrap 而非 Row：窄屏 + 长体积文本时会换行而不是溢出。
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (image.dangling)
                            const StatusBadge(
                              label: '悬空',
                              tone: BadgeTone.warning,
                              dense: true,
                            ),
                          StatusBadge(
                            label: image.usageUnknown
                                ? '引用数未知'
                                : image.inUse
                                ? '${image.containers} 个容器使用中'
                                : '未使用',
                            tone: image.inUse
                                ? BadgeTone.success
                                : BadgeTone.neutral,
                            dense: true,
                          ),
                          StatusBadge(
                            label: image.size.isEmpty ? '大小未知' : image.size,
                            tone: BadgeTone.info,
                            dense: true,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                A11yIconButton(
                  tooltip: '删除镜像 ${image.displayName}',
                  icon: Icon(
                    Icons.delete_outline,
                    color: theme.colorScheme.error,
                  ),
                  onPressed: onDelete,
                ),
              ],
            ),
            if (image.repoTags.length > 1) ...[
              const SizedBox(height: 8),
              TagWrap(values: image.repoTags.skip(1).toList()),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.tag, size: 13, color: theme.colorScheme.outline),
                const SizedBox(width: 4),
                Text(
                  image.shortIdText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                    fontFamily: 'monospace',
                    fontFamilyFallback: const ['Courier'],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  Icons.schedule,
                  size: 13,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    formatRelative(image.createdAt),
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
