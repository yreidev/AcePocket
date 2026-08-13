import 'package:flutter/material.dart';

/// 小号信息标签。
class InfoChip extends StatelessWidget {
  const InfoChip({
    super.key,
    required this.label,
    this.icon,
    this.color,
    this.background,
  });

  final String label;
  final IconData? icon;
  final Color? color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = color ?? theme.colorScheme.onSecondaryContainer;
    final bg = background ?? theme.colorScheme.secondaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          // 标签内容可能很长（服务器名、用户名、索引名），必须可收缩并省略，
          // 否则在 Wrap 里会撑破卡片宽度报 overflow。
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

/// 连接状态标签：valid 正常 / 其它异常。
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ok = status == 'valid';
    if (status.isEmpty) {
      return InfoChip(
        label: '未知',
        icon: Icons.help_outline,
        color: theme.colorScheme.onSurfaceVariant,
        background: theme.colorScheme.surfaceContainerHighest,
      );
    }
    return InfoChip(
      label: ok ? '正常' : '异常',
      icon: ok ? Icons.check_circle_outline : Icons.error_outline,
      color: ok
          ? theme.colorScheme.onTertiaryContainer
          : theme.colorScheme.onErrorContainer,
      background: ok
          ? theme.colorScheme.tertiaryContainer
          : theme.colorScheme.errorContainer,
    );
  }
}

/// 一行可换行的标签组。
class ChipRow extends StatelessWidget {
  const ChipRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 6, runSpacing: 6, children: children);
  }
}
