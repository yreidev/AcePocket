import 'package:flutter/material.dart';

import '../models/notify_channel.dart';
import 'alert_tiles.dart' show formatDateTime;
import 'form_fields.dart';

/// 通知渠道卡片。
class NotifyChannelTile extends StatelessWidget {
  const NotifyChannelTile({
    super.key,
    required this.channel,
    required this.onEdit,
    required this.onToggle,
    required this.onTest,
    required this.onDelete,
    this.busy = false,
  });

  final NotifyChannel channel;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onTest;
  final VoidCallback onDelete;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final smtp = channel.type == kNotifyTypeSmtp ? channel.smtp : null;

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
                      channel.name.isEmpty ? '未命名渠道' : channel.name,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusChip(
                    label: channel.enabled ? '已启用' : '已停用',
                    tone: channel.enabled ? ChipTone.success : ChipTone.neutral,
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
                          '${channel.name.isEmpty ? '未命名渠道' : channel.name}'
                          ' 的更多操作',
                      onSelected: (value) {
                        switch (value) {
                          case 'edit':
                            onEdit();
                          case 'test':
                            onTest();
                          case 'toggle':
                            onToggle();
                          case 'delete':
                            onDelete();
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'edit', child: Text('编辑')),
                        const PopupMenuItem(
                            value: 'test', child: Text('发送测试通知')),
                        PopupMenuItem(
                          value: 'toggle',
                          child: Text(channel.enabled ? '停用' : '启用'),
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
                  smtp == null || smtp.to.isEmpty
                      ? notifyTypeLabel(channel.type)
                      : '收件人：${channel.summary}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    StatusChip(label: notifyTypeLabel(channel.type)),
                    if (smtp != null)
                      StatusChip(label: '${smtp.host}:${smtp.port}'),
                    if (smtp != null)
                      StatusChip(label: smtpEncryptionLabel(smtp.encryption)),
                  ],
                ),
              ),
              if (channel.updatedAt != null) ...[
                const SizedBox(height: 8),
                Text(
                  '更新于 ${formatDateTime(channel.updatedAt)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
