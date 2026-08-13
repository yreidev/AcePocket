import 'package:flutter/material.dart';

export '../../../core/widgets/info_row.dart';

/// 可编辑的配置行：标题 + 当前值 +（可选）说明，点击进入编辑。
class SettingValueTile extends StatelessWidget {
  const SettingValueTile({
    super.key,
    required this.title,
    required this.value,
    this.onTap,
    this.icon,
    this.helper,
    this.busy = false,
    this.emptyText = '未设置',
    this.contentPadding = EdgeInsets.zero,
  });

  final String title;
  final String value;
  final String? helper;
  final IconData? icon;
  final bool busy;
  final String emptyText;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: contentPadding,
      leading: icon == null
          ? null
          : Icon(icon, color: theme.colorScheme.onSurfaceVariant),
      title: Text(title, style: theme.textTheme.bodyLarge),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value.isEmpty ? emptyText : value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: value.isEmpty
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.onSurface,
            ),
          ),
          if (helper != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                helper!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
      trailing: busy
          ? const BusyIndicator()
          : (onTap == null
              ? null
              : Icon(Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant)),
      onTap: busy ? null : onTap,
    );
  }
}

/// 20×20 的小号进度指示器（按钮 / 列表尾部占位）。
class BusyIndicator extends StatelessWidget {
  const BusyIndicator({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: const CircularProgressIndicator(strokeWidth: 2),
      );
}

/// 小标签（协议 / 状态 / 类型等）。
class TagChip extends StatelessWidget {
  const TagChip({super.key, required this.label, this.color, this.icon});

  final String label;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = color ?? theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: base.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: base),
            const SizedBox(width: 4),
          ],
          Text(label, style: theme.textTheme.labelSmall?.copyWith(color: base)),
        ],
      ),
    );
  }
}

/// 分区内的错误提示行（某个分区加载失败时使用），带重试按钮。
class SectionErrorTile extends StatelessWidget {
  const SectionErrorTile({
    super.key,
    required this.message,
    this.onRetry,
  });

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(Icons.error_outline, size: 20, color: theme.colorScheme.error),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: const Text('重试')),
      ],
    );
  }
}

/// 跑分成绩块：环形图标 + 分值 + 名称。
class ScoreTile extends StatelessWidget {
  const ScoreTile({
    super.key,
    required this.label,
    required this.score,
    required this.icon,
    this.running = false,
  });

  final String label;
  final int score;
  final IconData icon;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 72,
          height: 72,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 72,
                height: 72,
                child: CircularProgressIndicator(
                  value: running ? null : 1,
                  strokeWidth: 3,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    score > 0 ? color : theme.colorScheme.outlineVariant,
                  ),
                ),
              ),
              Icon(icon, size: 30, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          score > 0 ? '$score' : '未测试',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: score > 0
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
