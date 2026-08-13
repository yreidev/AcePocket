import 'package:flutter/material.dart';

import '../../../core/widgets/a11y.dart';
import '../models/ssh_host.dart';
import 'formatters.dart';

/// 主机卡片上的操作。
enum SshHostAction { terminal, files, edit, delete }

/// 已保存 SSH 主机的列表项。
class SshHostTile extends StatelessWidget {
  const SshHostTile({
    super.key,
    required this.host,
    required this.onAction,
    this.busy = false,
  });

  final SshHost host;
  final void Function(SshHostAction action) onAction;

  /// 该主机正在执行删除等操作，期间禁用全部入口，防止重复触发。
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
        onTap: busy ? null : () => onAction(SshHostAction.terminal),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.dns_outlined,
                  size: 22,
                  color: colorScheme.onPrimaryContainer,
                ),
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
                            host.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _AuthChip(method: host.config.authMethod),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      host.target,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (host.remark.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        host.remark.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      // 面板未返回更新时间时退回创建时间，文案随之改变，
                      // 避免把创建时间说成「更新于」。
                      host.updatedAt != null
                          ? '更新于 ${formatShortTime(host.updatedAt)}'
                          : host.createdAt != null
                          ? '创建于 ${formatShortTime(host.createdAt)}'
                          : '时间未知',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  A11yIconButton(
                    tooltip: '打开终端',
                    icon: const Icon(Icons.terminal_rounded),
                    onPressed: busy
                        ? null
                        : () => onAction(SshHostAction.terminal),
                  ),
                  PopupMenuButton<SshHostAction>(
                    tooltip: '更多操作',
                    enabled: !busy,
                    onSelected: onAction,
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: SshHostAction.files,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: Icon(Icons.folder_open_outlined),
                          title: Text('浏览文件'),
                        ),
                      ),
                      PopupMenuItem(
                        value: SshHostAction.edit,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: Icon(Icons.edit_outlined),
                          title: Text('编辑主机'),
                        ),
                      ),
                      PopupMenuItem(
                        value: SshHostAction.delete,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: Icon(Icons.delete_outline),
                          title: Text('删除主机'),
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
}

class _AuthChip extends StatelessWidget {
  const _AuthChip({required this.method});

  final SshAuthMethod method;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isKey = method == SshAuthMethod.publicKey;
    final background = isKey
        ? theme.colorScheme.tertiaryContainer
        : theme.colorScheme.secondaryContainer;
    final foreground = isKey
        ? theme.colorScheme.onTertiaryContainer
        : theme.colorScheme.onSecondaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        method.label,
        style: theme.textTheme.labelSmall?.copyWith(color: foreground),
      ),
    );
  }
}
