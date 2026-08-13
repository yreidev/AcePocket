import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/section_card.dart';

/// 首页快捷入口。
class QuickEntry {
  const QuickEntry({
    required this.label,
    required this.icon,
    required this.path,
    this.isTab = false,
  });

  final String label;
  final IconData icon;

  /// 目标路由（由各功能模块的 routes.dart 注册）。
  final String path;

  /// 目标是否为底部导航 tab 的根路由。
  ///
  /// tab 根路由属于 `StatefulShellRoute` 的分支，不能用 `push` 压栈，
  /// 必须用 `go` 切换分支。
  final bool isTab;
}

/// 默认快捷入口（外壳可通过 [HomePage.quickEntries] 覆盖以适配实际注册的路由）。
const List<QuickEntry> kDefaultQuickEntries = [
  QuickEntry(
    label: '网站',
    icon: Icons.language_rounded,
    path: '/websites',
    isTab: true,
  ),
  QuickEntry(label: '数据库', icon: Icons.storage_rounded, path: '/databases'),
  QuickEntry(label: '文件', icon: Icons.folder_outlined, path: '/files'),
  QuickEntry(label: '容器', icon: Icons.widgets_outlined, path: '/containers'),
  QuickEntry(label: '计划任务', icon: Icons.schedule_rounded, path: '/crons'),
  QuickEntry(label: '备份', icon: Icons.backup_outlined, path: '/backups'),
  QuickEntry(label: '证书', icon: Icons.verified_user_outlined, path: '/certs'),
  QuickEntry(label: '应用', icon: Icons.apps_rounded, path: '/apps'),
  QuickEntry(label: '终端', icon: Icons.terminal_rounded, path: '/terminal'),
  QuickEntry(label: '安全', icon: Icons.shield_outlined, path: '/security'),
  QuickEntry(label: '监控', icon: Icons.insights_rounded, path: '/monitor'),
  QuickEntry(label: '设置', icon: Icons.settings_outlined, path: '/settings'),
];

/// 快捷入口宫格（4 列）。
class QuickEntryGrid extends StatelessWidget {
  const QuickEntryGrid({super.key, this.entries = kDefaultQuickEntries});

  final List<QuickEntry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (entries.isEmpty) return const SizedBox.shrink();
    return SectionCard(
      title: '快捷入口',
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 0.95,
        ),
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () =>
                entry.isTab ? context.go(entry.path) : context.push(entry.path),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    entry.icon,
                    size: 22,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  entry.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
