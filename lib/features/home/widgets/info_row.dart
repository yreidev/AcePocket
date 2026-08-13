library;

export '../../../core/widgets/info_row.dart';

import 'package:flutter/material.dart';

import 'formatters.dart';

/// 竖排的「值 + 标签」小指标块，用于一行并排展示多个数值。
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.color,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = color ?? theme.colorScheme.primary;
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: tint),
            const SizedBox(height: 6),
          ],
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
              // 首页的负载 / 计数每 3 秒刷新一次，等宽数字避免整行左右抖动。
              fontFeatures: kTabularFigures,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: content,
    );
  }
}

/// 带标题与百分比的细进度条（磁盘 / 内存占用）。
class UsageBar extends StatelessWidget {
  const UsageBar({
    super.key,
    required this.title,
    required this.subtitle,
    required this.percent,
  });

  final String title;
  final String subtitle;

  /// 0-100。
  final double percent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 面板偶尔会返回 NaN / Infinity（分母为 0 的采样窗口）。NaN 通不过 clamp，
    // 会直接把 LinearProgressIndicator 的断言打挂，这里先归零。
    final safePercent = percent.isFinite ? percent : 0.0;
    final ratio = (safePercent / 100).clamp(0.0, 1.0);
    final color = safePercent >= 90
        ? theme.colorScheme.error
        : safePercent >= 75
            ? theme.colorScheme.tertiary
            : theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${safePercent.toStringAsFixed(1)}%',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontFeatures: kTabularFigures,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 卡片内部的小型错误提示（不打断整页展示），带重试按钮。
class InlineError extends StatelessWidget {
  const InlineError({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.error_outline, size: 18, color: theme.colorScheme.error),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: const Text('重试')),
      ],
    );
  }
}
