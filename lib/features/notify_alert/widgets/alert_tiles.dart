import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/alert_metric.dart';
import '../models/alert_rule.dart';
import 'form_fields.dart';

/// 面板返回的时间已在解析时 `toLocal()`，这里只负责格式化。
final DateFormat _dateTimeFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

String formatDateTime(DateTime? time) =>
    time == null ? '-' : _dateTimeFormat.format(time);

/// 告警规则卡片。
class AlertRuleTile extends StatelessWidget {
  const AlertRuleTile({
    super.key,
    required this.rule,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
    this.busy = false,
  });

  final AlertRule rule;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  /// 该条目正在执行操作（禁用交互）。
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final channelText = rule.channels.isEmpty
        ? '仅记录'
        : '${rule.channels.length} 个渠道';

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
        onTap: busy ? null : onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      rule.name.isEmpty ? '未命名规则' : rule.name,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusChip(
                    label: rule.enabled ? '已启用' : '已停用',
                    tone: rule.enabled ? ChipTone.success : ChipTone.neutral,
                  ),
                  if (busy)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    PopupMenuButton<String>(
                      tooltip:
                          '${rule.name.isEmpty ? '未命名规则' : rule.name} 的更多操作',
                      onSelected: (value) {
                        switch (value) {
                          case 'edit':
                            onEdit();
                          case 'toggle':
                            onToggle();
                          case 'delete':
                            onDelete();
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'edit', child: Text('编辑')),
                        PopupMenuItem(
                          value: 'toggle',
                          child: Text(rule.enabled ? '停用' : '启用'),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(
                            '删除',
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  rule.metricTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    StatusChip(
                      label: rule.conditionText,
                      tone: ChipTone.warning,
                    ),
                    StatusChip(label: '连续 ${rule.duration} 次'),
                    StatusChip(label: '静默 ${rule.silence} 分钟'),
                    StatusChip(
                      label: channelText,
                      tone: rule.channels.isEmpty
                          ? ChipTone.neutral
                          : ChipTone.success,
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

/// 告警记录卡片。
class AlertRecordTile extends StatelessWidget {
  const AlertRecordTile({super.key, required this.record});

  final AlertRecord record;

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
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    record.ruleName.isEmpty ? '未命名规则' : record.ruleName,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                StatusChip(
                  label: record.notified ? '已通知' : '未通知',
                  tone: record.notified ? ChipTone.success : ChipTone.neutral,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              record.message.isEmpty
                  ? '${record.metricTitle} 当前值 ${formatThreshold(record.value)}'
                  : record.message,
              // 面板返回的 message 偶尔很长，限制行数避免单条记录占满整屏。
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.schedule,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  formatDateTime(record.createdAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    record.metricTitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
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
