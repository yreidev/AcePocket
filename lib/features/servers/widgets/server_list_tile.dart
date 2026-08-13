import 'package:flutter/material.dart';

import '../../../core/models/server.dart';
import '../../../core/widgets/section_card.dart';

/// 服务器列表中的一张服务器卡片。
///
/// 点击整卡切换为当前服务器；右侧菜单提供设为当前 / 测试连接 / 编辑 / 删除。
class ServerListTile extends StatelessWidget {
  const ServerListTile({
    super.key,
    required this.server,
    required this.isActive,
    required this.onTap,
    required this.onTest,
    required this.onEdit,
    required this.onDelete,
  });

  final ServerConfig server;

  /// 是否为当前选中的服务器。
  final bool isActive;

  /// 点击整卡：切换为当前服务器。
  final VoidCallback onTap;

  /// 测试连接。
  final VoidCallback onTest;

  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      onTap: onTap,
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: isActive
                ? colorScheme.primaryContainer
                : colorScheme.surfaceContainerHighest,
            foregroundColor: isActive
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurfaceVariant,
            child: const Icon(Icons.dns_outlined),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        server.name.isEmpty ? '未命名服务器' : server.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    if (isActive) ...[
                      const SizedBox(width: 8),
                      _Badge(
                        text: '当前',
                        background: colorScheme.primaryContainer,
                        foreground: colorScheme.onPrimaryContainer,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${server.normalizedBaseUrl}${server.entrancePath}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                if (!server.hasCredentials) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 14,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '未填面板账号，终端 / 实时日志不可用',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: '更多操作',
            onSelected: (value) {
              switch (value) {
                case 'select':
                  onTap();
                case 'test':
                  onTest();
                case 'edit':
                  onEdit();
                case 'delete':
                  onDelete();
              }
            },
            itemBuilder: (context) => [
              if (!isActive)
                const PopupMenuItem<String>(
                  value: 'select',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.check_circle_outline),
                    title: Text('设为当前'),
                  ),
                ),
              const PopupMenuItem<String>(
                value: 'test',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.wifi_tethering_outlined),
                  title: Text('测试连接'),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'edit',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.edit_outlined),
                  title: Text('编辑'),
                ),
              ),
              PopupMenuItem<String>(
                value: 'delete',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline, color: colorScheme.error),
                  title: Text('删除', style: TextStyle(color: colorScheme.error)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.text,
    required this.background,
    required this.foreground,
  });

  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(color: foreground),
      ),
    );
  }
}
