import 'package:flutter/material.dart';

import '../../../core/widgets/a11y.dart';
import '../models/cron.dart';
import 'format.dart';

/// 计划任务列表项。
class CronTile extends StatelessWidget {
  const CronTile({
    super.key,
    required this.cron,
    required this.onToggle,
    required this.onRun,
    required this.onLog,
    required this.onEdit,
    required this.onDelete,
    this.busy = false,
  });

  final Cron cron;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRun;
  final VoidCallback onLog;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// 状态切换中，禁用开关。
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
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
                          cron.name,
                          style: theme.textTheme.titleSmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _Tag(
                              text: CronTypes.label(cron.type),
                              color: _typeColor(colorScheme, cron.type),
                            ),
                            if (cron.config.subType.isNotEmpty)
                              _Tag(
                                text: CronTypes.subTypeLabel(
                                  cron.type,
                                  cron.config.subType,
                                ),
                                color: colorScheme.secondaryContainer,
                                textColor: colorScheme.onSecondaryContainer,
                              ),
                            if (cron.config.flock)
                              _Tag(
                                text: '进程锁',
                                color: colorScheme.surfaceContainerHighest,
                                textColor: colorScheme.onSurfaceVariant,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  a11ySwitch(
                    // 只说明控制对象，开 / 关状态由 Switch 自己播报。
                    label: '计划任务 ${cron.name} 的启用状态',
                    child: Switch(
                      value: cron.status,
                      onChanged: busy ? null : onToggle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.schedule,
                    size: 15,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${describeCron(cron.time)}  ·  ${cron.time}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (cron.config.targets.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.adjust,
                      size: 15,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        cron.config.targets.join('、'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '更新于 ${formatDateTimeShort(cron.updatedAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.outline,
                      ),
                    ),
                  ),
                  A11yIconButton(
                    tooltip: '立即执行此任务',
                    icon: const Icon(Icons.play_arrow),
                    onPressed: onRun,
                  ),
                  A11yIconButton(
                    tooltip: '查看任务日志',
                    icon: const Icon(Icons.article_outlined),
                    onPressed: onLog,
                  ),
                  PopupMenuButton<String>(
                    tooltip: '更多任务操作',
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          onEdit();
                          break;
                        case 'delete':
                          onDelete();
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.edit_outlined),
                          title: Text('编辑'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.delete_outline,
                            color: colorScheme.error,
                          ),
                          title: Text(
                            '删除',
                            style: TextStyle(color: colorScheme.error),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Color _typeColor(ColorScheme scheme, String type) {
    switch (type) {
      case CronTypes.shell:
        return scheme.tertiaryContainer;
      case CronTypes.backup:
        return scheme.primaryContainer;
      default:
        return scheme.secondaryContainer;
    }
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color, this.textColor});

  final String text;
  final Color color;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: textColor ?? theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}
