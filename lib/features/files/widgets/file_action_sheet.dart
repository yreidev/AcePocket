import 'package:flutter/material.dart';

import '../models/file_item.dart';

/// 单个文件 / 目录可执行的操作。
enum FileAction {
  open,
  edit,
  rename,
  download,
  copy,
  cut,
  permission,
  compress,
  unCompress,
  share,
  truncate,
  copyPath,
  property,
  delete,
}

/// 展示单项操作面板，返回用户选择的操作；关闭时返回 null。
Future<FileAction?> showFileActionSheet(
  BuildContext context, {
  required FileItem item,
}) {
  return showModalBottomSheet<FileAction>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      final theme = Theme.of(context);
      Widget tile(
        IconData icon,
        String label,
        FileAction action, {
        bool danger = false,
      }) {
        final color = danger ? theme.colorScheme.error : null;
        return ListTile(
          dense: true,
          leading: Icon(icon, color: color),
          title: Text(label, style: TextStyle(color: color)),
          onTap: () => Navigator.of(context).pop(action),
        );
      }

      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.dir
                          ? '目录 · 权限 ${item.mode}'
                          : '${item.size.isEmpty ? '文件' : item.size} · 权限 ${item.mode}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (item.dir)
                tile(Icons.folder_open_outlined, '打开', FileAction.open)
              else
                tile(Icons.edit_note, '编辑内容', FileAction.edit),
              tile(Icons.drive_file_rename_outline, '重命名', FileAction.rename),
              if (!item.dir)
                tile(Icons.download_outlined, '下载到手机', FileAction.download),
              tile(Icons.copy_outlined, '复制', FileAction.copy),
              tile(Icons.content_cut, '剪切', FileAction.cut),
              tile(Icons.shield_outlined, '权限', FileAction.permission),
              tile(Icons.archive_outlined, '压缩', FileAction.compress),
              if (item.isArchive)
                tile(Icons.unarchive_outlined, '解压', FileAction.unCompress),
              if (!item.dir)
                tile(Icons.share_outlined, '创建分享链接', FileAction.share),
              if (!item.dir)
                tile(
                  Icons.cleaning_services_outlined,
                  '清空内容',
                  FileAction.truncate,
                ),
              tile(Icons.link, '复制路径', FileAction.copyPath),
              tile(Icons.info_outline, '属性', FileAction.property),
              const Divider(height: 1),
              tile(Icons.delete_outline, '删除', FileAction.delete, danger: true),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}
