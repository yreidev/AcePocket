import 'package:flutter/material.dart';

import '../models/webhook.dart';
import 'alert_tiles.dart' show formatDateTime;
import 'form_fields.dart';

/// WebHook 卡片。
class WebHookTile extends StatelessWidget {
  const WebHookTile({
    super.key,
    required this.webhook,
    required this.callbackUrl,
    required this.onEdit,
    required this.onToggle,
    required this.onCopyUrl,
    required this.onDelete,
    this.busy = false,
  });

  final WebHook webhook;

  /// 完整回调地址（`<面板地址>/webhook/<key>`）。
  final String callbackUrl;

  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onCopyUrl;
  final VoidCallback onDelete;
  final bool busy;

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
                      webhook.name.isEmpty ? '未命名 WebHook' : webhook.name,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusChip(
                    label: webhook.status ? '已启用' : '已停用',
                    tone: webhook.status ? ChipTone.success : ChipTone.neutral,
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
                          '${webhook.name.isEmpty ? '未命名 WebHook' : webhook.name}'
                          ' 的更多操作',
                      onSelected: (value) {
                        switch (value) {
                          case 'edit':
                            onEdit();
                          case 'copy':
                            onCopyUrl();
                          case 'toggle':
                            onToggle();
                          case 'delete':
                            onDelete();
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'edit', child: Text('编辑')),
                        const PopupMenuItem(
                          value: 'copy',
                          child: Text('复制回调地址'),
                        ),
                        PopupMenuItem(
                          value: 'toggle',
                          child: Text(webhook.status ? '停用' : '启用'),
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
                child: SelectableText(
                  callbackUrl,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    StatusChip(label: '用户 ${webhook.displayUser}'),
                    StatusChip(label: webhook.raw ? '原始输出' : 'JSON 输出'),
                    StatusChip(label: '调用 ${webhook.callCount} 次'),
                    if (webhook.lastCallAt != null)
                      StatusChip(
                        label: '最近 ${formatDateTime(webhook.lastCallAt)}',
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
