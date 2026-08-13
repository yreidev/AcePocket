import 'package:flutter/material.dart';

import '../../../core/widgets/a11y.dart';
import '../models/file_item.dart';

/// 路径面包屑：横向滚动展示各级目录，点击跳转；右侧提供「输入路径」入口。
///
/// 使用 `reverse: true` 的横向滚动，长路径默认展示末级目录。
class PathBreadcrumb extends StatelessWidget {
  const PathBreadcrumb({
    super.key,
    required this.path,
    required this.onNavigate,
    this.onEditPath,
  });

  /// 当前目录绝对路径。
  final String path;

  /// 点击某一级目录时回调（参数为该级的绝对路径）。
  final ValueChanged<String> onNavigate;

  /// 点击「手动输入路径」按钮的回调；为 null 时不展示该按钮。
  final VoidCallback? onEditPath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final segments = breadcrumbSegments(path);

    final children = <Widget>[];
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final isLast = i == segments.length - 1;
      children.add(
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: isLast ? null : () => onNavigate(segment.$2),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: segment.$2 == '/'
                ? Tooltip(
                    // 纯图标的根目录节点对读屏是匿名的，补上名称。
                    message: '根目录 /',
                    child: Icon(
                      Icons.storage_outlined,
                      size: 18,
                      color: isLast
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                : Text(
                    segment.$1,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isLast
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: isLast ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
          ),
        ),
      );
      if (!isLast) {
        children.add(
          Icon(Icons.chevron_right, size: 16, color: theme.colorScheme.outline),
        );
      }
    }

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(children: children),
            ),
          ),
          if (onEditPath != null)
            A11yIconButton(
              tooltip: '手动输入路径跳转',
              iconSize: 20,
              icon: const Icon(Icons.edit_location_alt_outlined),
              onPressed: onEditPath,
            ),
        ],
      ),
    );
  }
}
