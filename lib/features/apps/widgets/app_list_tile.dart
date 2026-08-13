import 'package:flutter/material.dart';

import '../../../core/widgets/a11y.dart';
import '../models/app_item.dart';

/// 应用商店列表项。
///
/// 展示应用名称、描述、分类、已安装版本与运行状态，
/// 并提供安装 / 更新 / 卸载 / 首页显示开关 / 自定义编译参数等操作入口。
class AppListTile extends StatelessWidget {
  const AppListTile({
    super.key,
    required this.app,
    required this.categoryLabels,
    required this.onInstall,
    required this.onUpdate,
    required this.onUninstall,
    required this.onToggleShow,
    required this.onCustom,
    this.busy = false,
  });

  final AppItem app;

  /// 分类 slug → 显示名。
  final Map<String, String> categoryLabels;

  final VoidCallback onInstall;
  final VoidCallback onUpdate;
  final VoidCallback onUninstall;
  final ValueChanged<bool> onToggleShow;
  final VoidCallback onCustom;

  /// 该应用是否有操作正在进行中（禁用按钮并展示进度）。
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AppAvatar(app: app),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              app.name.isEmpty ? app.slug : app.name,
                              style: theme.textTheme.titleMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (app.statusLabel != null) ...[
                            const SizedBox(width: 8),
                            _StatusChip(
                              status: app.status,
                              label: app.statusLabel!,
                            ),
                          ],
                        ],
                      ),
                      if (app.description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          app.description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _MetaWrap(app: app, categoryLabels: categoryLabels),
            const Divider(height: 16),
            _ActionRow(
              app: app,
              busy: busy,
              onInstall: onInstall,
              onUpdate: onUpdate,
              onUninstall: onUninstall,
              onToggleShow: onToggleShow,
              onCustom: onCustom,
            ),
          ],
        ),
      ),
    );
  }
}

class _AppAvatar extends StatelessWidget {
  const _AppAvatar({required this.app});

  final AppItem app;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final source = app.name.isNotEmpty ? app.name : app.slug;
    final letter = source.isEmpty ? '?' : source.substring(0, 1).toUpperCase();
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: app.installed
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        letter,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: app.installed
              ? colorScheme.onPrimaryContainer
              : colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.label});

  final String status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    late final Color background;
    late final Color foreground;
    switch (status) {
      case AppStatus.running:
        background = colorScheme.tertiaryContainer;
        foreground = colorScheme.onTertiaryContainer;
        break;
      case AppStatus.stopped:
        background = colorScheme.errorContainer;
        foreground = colorScheme.onErrorContainer;
        break;
      default:
        background = colorScheme.secondaryContainer;
        foreground = colorScheme.onSecondaryContainer;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: foreground),
      ),
    );
  }
}

class _MetaWrap extends StatelessWidget {
  const _MetaWrap({required this.app, required this.categoryLabels});

  final AppItem app;
  final Map<String, String> categoryLabels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final chips = <Widget>[];

    if (app.installed) {
      final version = app.installedVersion.isEmpty
          ? '未知版本'
          : app.installedVersion;
      final channel = app.installedChannel.isEmpty
          ? ''
          : ' · ${app.installedChannel}';
      chips.add(
        _MetaChip(
          icon: Icons.verified_outlined,
          label: '$version$channel',
          color: colorScheme.primary,
        ),
      );
      if (app.updateExist) {
        chips.add(
          _MetaChip(
            icon: Icons.upgrade,
            label: app.targetVersion.isEmpty
                ? '有新版本'
                : '可更新至 ${app.targetVersion}',
            color: colorScheme.tertiary,
          ),
        );
      }
    } else if (app.channels.isNotEmpty) {
      chips.add(
        _MetaChip(
          icon: Icons.inventory_2_outlined,
          label: '${app.channels.length} 个版本可选',
          color: colorScheme.onSurfaceVariant,
        ),
      );
    }

    for (final category in app.categories) {
      chips.add(
        _MetaChip(
          icon: Icons.label_outline,
          label: categoryLabels[category] ?? category,
          color: colorScheme.onSurfaceVariant,
        ),
      );
    }

    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 4, children: chips);
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 3),
        // Wrap 给子项的是宽度上界为整行的松约束，Row 内非 Flexible 的 Text
        // 会以无限宽度布局：版本号 / 分类名较长时会直接溢出。
        Flexible(
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.app,
    required this.busy,
    required this.onInstall,
    required this.onUpdate,
    required this.onUninstall,
    required this.onToggleShow,
    required this.onCustom,
  });

  final AppItem app;
  final bool busy;
  final VoidCallback onInstall;
  final VoidCallback onUpdate;
  final VoidCallback onUninstall;
  final ValueChanged<bool> onToggleShow;
  final VoidCallback onCustom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        if (app.installed)
          Expanded(
            child: a11ySwitch(
              // 读屏播报「<应用> 在面板首页的显示」+ 开关自身的开 / 关状态，
              // 避免同屏多个同名开关无法区分。
              label: '${app.name.isEmpty ? app.slug : app.name} 在面板首页的显示',
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      '首页显示',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Switch(
                    value: app.show,
                    onChanged: busy ? null : onToggleShow,
                  ),
                ],
              ),
            ),
          )
        else
          const Spacer(),
        if (busy)
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        if (!app.installed)
          FilledButton.tonal(
            onPressed: busy ? null : onInstall,
            child: const Text('安装'),
          )
        else ...[
          if (app.updateExist)
            TextButton(
              onPressed: busy ? null : onUpdate,
              child: const Text('更新'),
            ),
          TextButton(
            onPressed: busy ? null : onUninstall,
            style: TextButton.styleFrom(foregroundColor: colorScheme.error),
            child: const Text('卸载'),
          ),
        ],
        if (app.customSupported)
          A11yIconButton(
            tooltip: '编辑 ${app.name.isEmpty ? app.slug : app.name} 的编译参数',
            onPressed: busy ? null : onCustom,
            icon: const Icon(Icons.tune, size: 20),
          ),
      ],
    );
  }
}
