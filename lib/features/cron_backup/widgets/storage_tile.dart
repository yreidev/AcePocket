import 'package:flutter/material.dart';

import '../../../core/widgets/a11y.dart';
import '../models/backup_storage.dart';
import 'format.dart';

/// 备份存储列表项。
class StorageTile extends StatelessWidget {
  const StorageTile({
    super.key,
    required this.storage,
    required this.onEdit,
    required this.onDelete,
  });

  final BackupStorage storage;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// 摘要信息：不同类型展示不同的关键字段。
  String get _summary {
    final info = storage.info;
    switch (storage.type) {
      case BackupStorageTypes.local:
        return info.path.isEmpty ? '面板默认备份目录' : info.path;
      case BackupStorageTypes.s3:
        final bucket = info.bucket.isEmpty ? '-' : info.bucket;
        final endpoint = info.endpoint.isEmpty ? '-' : info.endpoint;
        return '$bucket @ $endpoint';
      case BackupStorageTypes.sftp:
        final host = info.host.isEmpty ? '-' : info.host;
        return '${info.username}@$host:${info.port}${info.path}';
      case BackupStorageTypes.webdav:
        return info.url.isEmpty ? '-' : '${info.url}${info.path}';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isLocal = storage.isLocal;
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
        onTap: isLocal ? null : onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isLocal ? Icons.folder_outlined : Icons.cloud_outlined,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      storage.name,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      BackupStorageTypes.label(storage.type),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _summary,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      isLocal
                          ? '面板本地存储，不可编辑'
                          : '创建于 ${formatDateTimeShort(storage.createdAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.outline,
                      ),
                    ),
                  ),
                  if (!isLocal) ...[
                    A11yIconButton(
                      tooltip: '编辑此备份存储',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: onEdit,
                    ),
                    A11yIconButton(
                      tooltip: '删除此备份存储',
                      icon: Icon(
                        Icons.delete_outline,
                        color: colorScheme.error,
                      ),
                      onPressed: onDelete,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
