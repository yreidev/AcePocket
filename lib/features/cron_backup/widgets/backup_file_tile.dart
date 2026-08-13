import 'package:flutter/material.dart';

import '../../../core/widgets/a11y.dart';
import '../models/backup_file.dart';
import 'format.dart';

/// 备份文件列表项。
class BackupFileTile extends StatelessWidget {
  const BackupFileTile({
    super.key,
    required this.file,
    required this.onInfo,
    this.onDownload,
    this.onRestore,
    this.onDelete,
  });

  final BackupFile file;

  /// 查看文件信息 / 路径。
  final VoidCallback onInfo;

  /// 下载到本机；为 null 表示不提供下载。
  final VoidCallback? onDownload;

  /// 为 null 表示该类型不支持恢复。
  final VoidCallback? onRestore;

  /// 为 null 表示该类型不支持删除。
  final VoidCallback? onDelete;

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
        onTap: onInfo,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.archive_outlined,
                      size: 18, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      file.name,
                      style: theme.textTheme.bodyLarge,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${file.size.isEmpty ? '-' : file.size}  ·  '
                '${formatDateTime(file.time)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      file.path,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.outline,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  A11yIconButton(
                    tooltip: '查看备份文件信息',
                    icon: const Icon(Icons.info_outline),
                    onPressed: onInfo,
                  ),
                  if (onDownload != null)
                    A11yIconButton(
                      tooltip: '下载备份到本机',
                      icon: const Icon(Icons.download_outlined),
                      onPressed: onDownload,
                    ),
                  if (onRestore != null)
                    A11yIconButton(
                      tooltip: '用此备份恢复',
                      icon: const Icon(Icons.settings_backup_restore),
                      onPressed: onRestore,
                    ),
                  if (onDelete != null)
                    A11yIconButton(
                      tooltip: '删除此备份',
                      icon:
                          Icon(Icons.delete_outline, color: colorScheme.error),
                      onPressed: onDelete,
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
