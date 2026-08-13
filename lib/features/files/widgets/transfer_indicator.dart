import 'package:flutter/material.dart';

import '../../../core/utils/format.dart';

/// 把字节数格式化为可读大小。
///
/// 体积换算统一走 core 的 [formatBytes]（1024 进制、两位小数、边界安全），
/// 这里只保留传输场景特有的语义：总量未知时约定传 -1，展示为「未知」。
String formatTransferBytes(int bytes) {
  if (bytes < 0) return '未知';
  return formatBytes(bytes);
}

/// 把速度（字节/秒）格式化为可读文本。
String formatTransferSpeed(double bytesPerSecond) {
  if (bytesPerSecond <= 0) return '';
  return '${formatTransferBytes(bytesPerSecond.round())}/s';
}

/// 传输进度展示区：标题、进度条、已传输 / 总量与速度。
class TransferIndicator extends StatelessWidget {
  const TransferIndicator({
    super.key,
    required this.title,
    required this.transferred,
    required this.total,
    this.speed = '',
    this.subtitle,
  });

  /// 当前传输的文件名。
  final String title;

  /// 已传输字节数。
  final int transferred;

  /// 总字节数，未知时传 -1（进度条转为不确定态）。
  final int total;

  /// 已格式化的速度文本，空串表示不展示。
  final String speed;

  /// 附加说明（如「第 2 / 5 个文件」）。
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final double? value = total > 0
        ? (transferred / total).clamp(0.0, 1.0)
        : null;
    final percent = value == null ? '' : '${(value * 100).floor()}%';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (subtitle != null) ...[
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
        ],
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: value, minHeight: 6),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                total > 0
                    ? '${formatTransferBytes(transferred)} / '
                          '${formatTransferBytes(total)}'
                    : formatTransferBytes(transferred),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 百分比 + 速度在窄屏 / 大字号下会顶破 Row，必须可收缩。
            Flexible(
              child: Text(
                [percent, speed].where((e) => e.isNotEmpty).join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
