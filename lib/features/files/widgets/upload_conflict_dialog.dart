import 'package:flutter/material.dart';

/// 上传时目标已存在的处理方式。
enum UploadConflictAction {
  /// 覆盖服务器上的同名文件（`force = true`）。
  overwrite,

  /// 自动改名上传（追加 `-1`、`-2`…）。
  rename,

  /// 跳过这些文件，只上传不冲突的部分。
  skip,
}

/// 上传冲突处理对话框。返回 null 表示用户放弃整次上传。
Future<UploadConflictAction?> showUploadConflictDialog(
  BuildContext context, {
  required List<String> names,
}) {
  return showDialog<UploadConflictAction>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      const previewLimit = 8;
      final preview = names.take(previewLimit).toList();
      final hintStyle = theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      );
      return AlertDialog(
        // 冲突文件多 / 文件名长时内容会超出屏幕高度，交给对话框自身滚动。
        scrollable: true,
        title: const Text('目标已存在'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '以下 ${names.length} 个文件在目标目录已存在：',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              // 逐行渲染而非拼接成一个字符串：长文件名可以单独省略，
              // 不会把对话框撑出横向溢出。
              for (final name in preview)
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: hintStyle,
                ),
              if (names.length > previewLimit)
                Text('… 等共 ${names.length} 个', style: hintStyle),
              const SizedBox(height: 12),
              Text('请选择处理方式，该选择对本次上传的全部冲突文件生效。', style: hintStyle),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('放弃上传'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(UploadConflictAction.skip),
            child: const Text('跳过冲突'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(UploadConflictAction.rename),
            child: const Text('自动改名'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(UploadConflictAction.overwrite),
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            child: const Text('覆盖'),
          ),
        ],
      );
    },
  );
}
