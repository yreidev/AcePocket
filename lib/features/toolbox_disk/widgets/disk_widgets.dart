/// 磁盘工具箱内部复用的展示型小组件。
///
/// 提示与格式化统一走 core，不在本模块自带副本：
/// 成功 / 错误提示用 `core/widgets/app_snack.dart`，
/// 字节格式化用 `core/utils/format.dart` 的 `formatBytes`。
library;

import 'package:flutter/material.dart';

import '../../../core/widgets/info_row.dart' as core;

/// 磁盘工具箱信息行：值可选择复制（设备路径、序列号等）。
class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.label,
    required this.value,
    this.monospace = false,
    this.valueColor,
    this.labelWidth = 92,
  });

  final String label;
  final String value;
  final bool monospace;
  final Color? valueColor;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    return core.InfoRow(
      label: label,
      value: value,
      monospace: monospace,
      valueColor: valueColor,
      labelWidth: labelWidth,
      selectable: true,
      emptyPlaceholder: '-',
    );
  }
}

/// 小标签（分区类型 / 文件系统 / 状态等）。
///
/// 文案单行省略：RAID / SMART 的状态字段来自 `mdadm`、`storcli` 等命令的原始
/// 输出，偶尔会是「Optimal (Rebuilding 12%)」这类长串。标签本身按内容自适应
/// 宽度，放在 [Row] 里时**调用方要用 [Flexible] 包住**，否则同排的 [Expanded]
/// 会被挤成 0 宽并触发溢出。
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
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(color: base),
          ),
        ],
      ),
    );
  }
}

/// 使用率进度条：>90% 红、>70% 橙、其余主色。
class UsageBar extends StatelessWidget {
  const UsageBar({super.key, required this.percent, this.width});

  final int percent;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clamped = percent.clamp(0, 100);
    final color = clamped > 90
        ? theme.colorScheme.error
        : clamped > 70
            ? theme.colorScheme.tertiary
            : theme.colorScheme.primary;
    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: clamped / 100,
        minHeight: 6,
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
    return Row(
      children: [
        Expanded(
            child: width == null ? bar : SizedBox(width: width, child: bar)),
        const SizedBox(width: 8),
        Text(
          '$clamped%',
          style: theme.textTheme.labelSmall?.copyWith(color: color),
        ),
      ],
    );
  }
}

/// 页面内的提示条（警告 / 说明）。
class NoticeBar extends StatelessWidget {
  const NoticeBar({
    super.key,
    required this.text,
    this.icon = Icons.info_outline,
    this.danger = false,
  });

  final String text;
  final IconData icon;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = danger
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onSurfaceVariant;
    final bg = danger
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.surfaceContainerHighest;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

/// 列表内的小型加载遮罩（操作执行中）。
///
/// [semanticsLabel] 会被读屏播报，默认「操作执行中」——按钮在执行期间被替换成
/// 本组件，若没有语义标签，TalkBack 用户只会感觉按钮凭空消失。
class BusyIndicator extends StatelessWidget {
  const BusyIndicator({
    super.key,
    this.size = 18,
    this.semanticsLabel = '操作执行中',
  });

  final double size;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          semanticsLabel: semanticsLabel,
        ),
      );
}
