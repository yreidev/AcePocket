import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/format.dart';
import '../../../core/widgets/a11y.dart';
import '../models/container_compose.dart';
import '../models/json_utils.dart';
import '../providers/container_providers.dart';
import '../widgets/compose_actions.dart';
import '../widgets/compose_create_sheet.dart';
import '../widgets/paged_list_view.dart';
import '../widgets/status_badge.dart';

/// 编排管理页（`/containers/compose`）。
class ComposeListPage extends ConsumerWidget {
  const ComposeListPage({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = await showComposeCreateSheet(context);
    if (name == null) return;
    await ref.read(containerComposesProvider.notifier).reload();
    if (context.mounted) {
      unawaited(context.push('/containers/compose/$name'));
    }
  }

  Future<void> _handle(
    BuildContext context,
    WidgetRef ref,
    ContainerCompose compose,
    _ComposeMenu action,
  ) async {
    var ok = false;
    switch (action) {
      case _ComposeMenu.up:
        ok = await composeUpAction(context, ref, compose.name);
        break;
      case _ComposeMenu.down:
        ok = await composeDownAction(context, ref, compose.name);
        break;
      case _ComposeMenu.remove:
        ok = await composeRemoveAction(context, ref, compose.name);
        break;
    }
    if (!ok) return;
    ref.invalidate(composeDetailProvider(compose.name));
    ref.invalidate(containersProvider);
    await ref.read(containerComposesProvider.notifier).reload();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(containerComposesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('编排管理'),
        actions: [
          A11yIconButton(
            tooltip: '刷新编排列表',
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.read(containerComposesProvider.notifier).reload(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('新建编排'),
      ),
      body: PagedListView<ContainerCompose>(
        state: state,
        loadingMessage: '正在加载编排列表…',
        emptyMessage: '还没有任何编排',
        emptyIcon: Icons.dashboard_customize_outlined,
        emptyAction: FilledButton.icon(
          onPressed: () => _create(context, ref),
          icon: const Icon(Icons.add),
          label: const Text('新建编排'),
        ),
        onRefresh: () => ref.read(containerComposesProvider.notifier).refresh(),
        onLoadMore: () =>
            ref.read(containerComposesProvider.notifier).loadMore(),
        onRetry: () => ref.invalidate(containerComposesProvider),
        itemBuilder: (context, compose, _) => _ComposeTile(
          compose: compose,
          onTap: () => context.push('/containers/compose/${compose.name}'),
          onAction: (action) => _handle(context, ref, compose, action),
        ),
      ),
    );
  }
}

enum _ComposeMenu { up, down, remove }

class _ComposeTile extends StatelessWidget {
  const _ComposeTile({
    required this.compose,
    required this.onTap,
    required this.onAction,
  });

  final ContainerCompose compose;
  final VoidCallback onTap;
  final ValueChanged<_ComposeMenu> onAction;

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
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
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
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                compose.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall,
                              ),
                            ),
                            const SizedBox(width: 8),
                            StatusBadge(
                              label: compose.statusLabel,
                              tone: compose.isRunning
                                  ? BadgeTone.success
                                  : compose.isUnknown
                                  ? BadgeTone.neutral
                                  : BadgeTone.warning,
                              dense: true,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          compose.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontFamily: 'monospace',
                            fontFamilyFallback: const ['Courier'],
                          ),
                        ),
                      ],
                    ),
                  ),
                  A11yIconButton(
                    tooltip: '启动编排 ${compose.name}',
                    icon: const Icon(Icons.play_arrow_outlined),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => onAction(_ComposeMenu.up),
                  ),
                  PopupMenuButton<_ComposeMenu>(
                    tooltip: '${compose.name} 的更多操作',
                    icon: const Icon(Icons.more_vert),
                    onSelected: onAction,
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: _ComposeMenu.up,
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.play_arrow_outlined),
                          title: Text('启动'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: _ComposeMenu.down,
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.stop_outlined),
                          title: Text('停止'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _ComposeMenu.remove,
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.delete_outline,
                            color: theme.colorScheme.error,
                          ),
                          title: Text(
                            '删除',
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
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
                      formatDateTime(compose.createdAt),
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
      ),
    );
  }
}
