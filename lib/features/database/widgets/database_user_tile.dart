import 'package:flutter/material.dart';

import '../../../core/widgets/section_card.dart';
import '../models/database_user.dart';
import '../models/db_types.dart';
import 'db_chips.dart';

/// 数据库用户列表条目。
class DatabaseUserTile extends StatelessWidget {
  const DatabaseUserTile({
    super.key,
    required this.user,
    required this.onEdit,
    required this.onChangePassword,
    required this.onEditRemark,
    required this.onDelete,
  });

  final DatabaseUser user;
  final VoidCallback onEdit;
  final VoidCallback onChangePassword;
  final VoidCallback onEditRemark;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final serverType = user.server?.type ?? '';
    final title = user.host.isEmpty
        ? user.username
        : '${user.username}@${user.host}';
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      onTap: onEdit,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.person_outline, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusChip(status: user.status),
                  ],
                ),
                const SizedBox(height: 6),
                ChipRow(
                  children: [
                    if (serverType.isNotEmpty)
                      InfoChip(label: dbTypeLabel(serverType)),
                    if (user.server != null)
                      InfoChip(
                        label: user.server!.name,
                        icon: Icons.dns_outlined,
                        color: theme.colorScheme.onSurfaceVariant,
                        background: theme.colorScheme.surfaceContainerHighest,
                      ),
                  ],
                ),
                if (user.privileges.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '授权：${user.privileges.join('、')}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (user.remark.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    user.remark,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: '更多操作',
            onSelected: (value) {
              switch (value) {
                case 'edit':
                  onEdit();
                case 'password':
                  onChangePassword();
                case 'remark':
                  onEditRemark();
                case 'delete':
                  onDelete();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.edit_outlined),
                  title: Text('编辑用户'),
                ),
              ),
              const PopupMenuItem(
                value: 'password',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.key_outlined),
                  title: Text('修改密码'),
                ),
              ),
              const PopupMenuItem(
                value: 'remark',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.notes_outlined),
                  title: Text('修改备注'),
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.delete_outline,
                    color: theme.colorScheme.error,
                  ),
                  title: Text(
                    '删除用户',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
