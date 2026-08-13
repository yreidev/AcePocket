import 'package:flutter/material.dart';

import '../../../core/utils/format.dart' hide formatDateTime;
import '../../../core/widgets/a11y.dart';
import '../models/ssh_file_info.dart';
import 'formatters.dart';

/// SFTP 目录中的一个条目。
///
/// 目录 / 软链接可点击进入，普通文件点击展示详情（由 [onTap] 决定）。
class SftpFileTile extends StatelessWidget {
  const SftpFileTile({
    super.key,
    required this.file,
    required this.onTap,
    required this.onShowInfo,
  });

  final SshFileInfo file;
  final VoidCallback onTap;
  final VoidCallback onShowInfo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final IconData icon;
    final Color iconColor;
    if (file.isDir) {
      icon = Icons.folder_rounded;
      iconColor = colorScheme.primary;
    } else if (file.isLink) {
      icon = Icons.link_rounded;
      iconColor = colorScheme.tertiary;
    } else {
      icon = Icons.insert_drive_file_outlined;
      iconColor = colorScheme.onSurfaceVariant;
    }

    final subtitle = <String>[
      if (!file.isDir) formatBytes(file.size),
      if (file.mode.isNotEmpty) file.mode,
      formatShortTime(file.modTime),
    ].join(' · ');

    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(
        file.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium,
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: A11yIconButton(
        tooltip: '查看「${file.name}」详情',
        icon: const Icon(Icons.info_outline, size: 20),
        onPressed: onShowInfo,
      ),
      onTap: onTap,
      onLongPress: onShowInfo,
    );
  }
}

/// 文件详情弹窗（SFTP 接口只提供只读信息，不含权限修改能力）。
Future<void> showSftpFileInfoDialog(
  BuildContext context, {
  required SshFileInfo file,
  required String directory,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      final rows = <(String, String)>[
        ('名称', file.name),
        ('路径', joinPath(directory, file.name)),
        (
          '类型',
          file.isDir
              ? '目录'
              : file.isLink
              ? '软链接'
              : '文件',
        ),
        if (!file.isDir) ('大小', '${formatBytes(file.size)}（${file.size} 字节）'),
        ('权限', file.mode.isEmpty ? '—' : file.mode),
        ('修改时间', formatDateTime(file.modTime)),
      ];
      return AlertDialog(
        title: const Text('文件详情'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 64,
                        child: Text(
                          row.$1,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Expanded(
                        child: SelectableText(
                          row.$2,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      );
    },
  );
}
