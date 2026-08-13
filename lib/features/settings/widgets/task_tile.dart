import 'package:flutter/material.dart';

import '../models/task_item.dart';
import 'format_utils.dart';

/// 任务状态对应的配色（从 Theme 取，不硬编码颜色值）。
({Color background, Color foreground}) taskStatusColors(
  BuildContext context,
  String status,
) {
  final scheme = Theme.of(context).colorScheme;
  switch (status) {
    case TaskItem.statusRunning:
      return (
        background: scheme.primaryContainer,
        foreground: scheme.onPrimaryContainer,
      );
    case TaskItem.statusFinished:
      return (
        background: scheme.secondaryContainer,
        foreground: scheme.onSecondaryContainer,
      );
    case TaskItem.statusFailed:
      return (
        background: scheme.errorContainer,
        foreground: scheme.onErrorContainer,
      );
    case TaskItem.statusCanceled:
      return (
        background: scheme.surfaceContainerHighest,
        foreground: scheme.onSurfaceVariant,
      );
    default: // waiting
      return (
        background: scheme.tertiaryContainer,
        foreground: scheme.onTertiaryContainer,
      );
  }
}

/// 任务状态标签。
class TaskStatusChip extends StatelessWidget {
  const TaskStatusChip({super.key, required this.status, this.label});

  final String status;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = taskStatusColors(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == TaskItem.statusRunning) ...[
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.foreground,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label ?? status,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.foreground,
            ),
          ),
        ],
      ),
    );
  }
}

/// 任务列表项。
class TaskTile extends StatelessWidget {
  const TaskTile({
    super.key,
    required this.task,
    required this.onTap,
    required this.onCancel,
    required this.onDelete,
  });

  final TaskItem task;
  final VoidCallback onTap;
  final VoidCallback onCancel;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            task.name.isEmpty ? '任务 #${task.id}' : task.name,
                            style: theme.textTheme.titleSmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        TaskStatusChip(
                          status: task.status,
                          label: task.statusLabel,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '创建：${formatDateTime(task.createdAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      '更新：${formatDateTime(task.updatedAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '该任务的更多操作',
                onSelected: (value) {
                  if (value == 'cancel') onCancel();
                  if (value == 'delete') onDelete();
                  if (value == 'detail') onTap();
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'detail',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.article_outlined),
                      title: Text('详情与日志'),
                    ),
                  ),
                  if (task.isActive)
                    const PopupMenuItem(
                      value: 'cancel',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.stop_circle_outlined),
                        title: Text('取消任务'),
                      ),
                    )
                  else
                    PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
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
        ),
      ),
    );
  }
}
