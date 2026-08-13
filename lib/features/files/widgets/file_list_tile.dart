import 'package:flutter/material.dart';

import '../../../core/widgets/a11y.dart';
import '../models/file_item.dart';

/// 文件 / 目录列表项。
///
/// 支持选择模式（左侧显示复选框）、长按进入多选、右侧「更多操作」按钮。
class FileListTile extends StatelessWidget {
  const FileListTile({
    super.key,
    required this.item,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    this.onMore,
  });

  final FileItem item;

  /// 是否处于多选模式。
  final bool selectionMode;

  /// 当前项是否被选中。
  final bool selected;

  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// 点击右侧「更多」按钮；选择模式下不展示。
  final VoidCallback? onMore;

  IconData get _icon {
    if (item.dir) return Icons.folder_outlined;
    if (item.symlink) return Icons.link;
    if (item.isArchive) return Icons.folder_zip_outlined;
    final name = item.name.toLowerCase();
    if (name.endsWith('.png') ||
        name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.gif') ||
        name.endsWith('.webp') ||
        name.endsWith('.svg') ||
        name.endsWith('.ico')) {
      return Icons.image_outlined;
    }
    if (name.endsWith('.sh') || name.endsWith('.bash')) {
      return Icons.terminal;
    }
    if (name.endsWith('.log')) return Icons.article_outlined;
    if (name.endsWith('.conf') ||
        name.endsWith('.ini') ||
        name.endsWith('.yaml') ||
        name.endsWith('.yml') ||
        name.endsWith('.toml') ||
        name.endsWith('.json')) {
      return Icons.settings_outlined;
    }
    return Icons.description_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitleParts = <String>[
      item.modify,
      if (!item.dir && item.size.isNotEmpty) item.size,
      item.mode,
      '${item.owner}:${item.group}',
    ].where((e) => e.isNotEmpty).toList();

    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      selected: selected,
      selectedTileColor: theme.colorScheme.primaryContainer.withValues(
        alpha: 0.35,
      ),
      leading: selectionMode
          ? Checkbox(value: selected, onChanged: (_) => onTap())
          : Icon(
              _icon,
              color: item.dir
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: item.hidden
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.onSurface,
              ),
            ),
          ),
          if (item.immutable) ...[
            const SizedBox(width: 6),
            // Tooltip 同时提供长按提示与读屏播报，纯图标对盲用户不可见。
            Tooltip(
              message: '已加防篡改锁定（chattr +i）',
              child: Icon(
                Icons.lock_outline,
                size: 14,
                color: theme.colorScheme.tertiary,
              ),
            ),
          ],
          if (item.symlink) ...[
            const SizedBox(width: 6),
            Icon(
              Icons.arrow_forward,
              size: 14,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(width: 2),
            Flexible(
              child: Text(
                item.link,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        subtitleParts.join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: selectionMode
          ? null
          : A11yIconButton(
              icon: const Icon(Icons.more_vert),
              // 读屏会连同列表项标题一起播报，这里点明操作对象。
              tooltip: '${item.name} 的更多操作',
              onPressed: onMore,
            ),
    );
  }
}
