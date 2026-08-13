import 'package:flutter/material.dart';

import '../../../core/utils/format.dart';
import '../../../core/widgets/a11y.dart';
import '../models/container.dart';
import '../models/json_utils.dart';
import 'container_actions.dart';
import 'info_row.dart';
import 'status_badge.dart';

/// 容器列表项。
class ContainerTile extends StatelessWidget {
  const ContainerTile({
    super.key,
    required this.item,
    required this.onTap,
    required this.onAction,
    required this.onShowLogs,
  });

  final ContainerItem item;
  final VoidCallback onTap;
  final ValueChanged<ContainerAction> onAction;
  final VoidCallback onShowLogs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actions = availableContainerActions(item.state);

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
                                item.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall,
                              ),
                            ),
                            const SizedBox(width: 8),
                            ContainerStateBadge(state: item.state, dense: true),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.image.isEmpty ? '-' : item.image,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 紧凑密度会把触摸目标压到 40dp 以下，A11yIconButton 兜底 48。
                  A11yIconButton(
                    tooltip: '查看 ${item.displayName} 的实时日志',
                    icon: const Icon(Icons.subject_outlined),
                    visualDensity: VisualDensity.compact,
                    onPressed: onShowLogs,
                  ),
                  PopupMenuButton<ContainerAction>(
                    tooltip: '${item.displayName} 的更多操作',
                    icon: const Icon(Icons.more_vert),
                    onSelected: onAction,
                    itemBuilder: (context) => [
                      for (final action in actions)
                        PopupMenuItem<ContainerAction>(
                          value: action,
                          child: Row(
                            children: [
                              Icon(
                                action.icon,
                                size: 20,
                                color: action.danger
                                    ? theme.colorScheme.error
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                action.label,
                                style: action.danger
                                    ? TextStyle(color: theme.colorScheme.error)
                                    : null,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (item.status.isNotEmpty)
                      Text(
                        item.status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    if (item.portTexts.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      TagWrap(values: item.portTexts.take(4).toList()),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.tag,
                          size: 13,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          item.shortId,
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
                            formatRelative(item.createdAt),
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
            ],
          ),
        ),
      ),
    );
  }
}
