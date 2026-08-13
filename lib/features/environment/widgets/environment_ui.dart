import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/widgets/app_snack.dart';

/// 复制文本到剪贴板并提示。
Future<void> copyToClipboard(BuildContext context, String text,
    {String label = '已复制'}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  showSuccessSnack(context, label);
}

/// 环境类型对应的图标。
IconData environmentTypeIcon(String type) {
  switch (type) {
    case 'php':
      return Icons.php_rounded;
    case 'nodejs':
      return Icons.javascript_rounded;
    case 'java':
      return Icons.coffee_rounded;
    case 'go':
      return Icons.bolt_rounded;
    case 'python':
      return Icons.data_object_rounded;
    case 'dotnet':
      return Icons.window_rounded;
    default:
      return Icons.terminal_rounded;
  }
}

/// 环境类型的中文 / 通用展示名（`/environment/types` 不可用时的兜底）。
String environmentTypeLabel(String type) {
  switch (type) {
    case 'php':
      return 'PHP';
    case 'nodejs':
      return 'Node.js';
    case 'java':
      return 'Java';
    case 'go':
      return 'Go';
    case 'python':
      return 'Python';
    case 'dotnet':
      return '.NET';
    default:
      return type.isEmpty ? '其他' : type;
  }
}

/// 面板用无点写法表示 PHP 版本（`83` 即 8.3），展示时补回小数点。
///
/// 各页面标题统一走这里，避免同一版本在「PHP 8.3」与「PHP 83」之间摇摆。
String phpVersionText(int version) {
  final raw = '$version';
  if (raw.length < 2) return raw;
  return '${raw.substring(0, raw.length - 1)}.${raw.substring(raw.length - 1)}';
}

/// PHP-FPM 负载值美化：`start time` 之类的 Unix 秒时间戳转本地时间展示。
///
/// 面板把 php-fpm status 的原始值原样 `cast.ToString`，
/// 启动时间是 Unix 秒时间戳，直接展示为数字对用户无意义。
String formatLoadValue(String name, String value) {
  final isTimeField =
      name.contains('时间') || name.toLowerCase().contains('time');
  if (!isTimeField) return value;
  final seconds = int.tryParse(value.trim());
  if (seconds == null || seconds < 1000000000 || seconds > 99999999999) {
    return value;
  }
  final time = DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true)
      .toLocal();
  return DateFormat('yyyy-MM-dd HH:mm:ss').format(time);
}

/// `GET /environment/is_installed` 的探测结果文案。
String probeText(AsyncValue<bool> probe) => probe.when(
      loading: () => '检测中…',
      error: (error, _) => '检测失败（${describeError(error)}）',
      data: (value) => value ? '已安装' : '未安装',
    );

/// 键值展示行（左标题、右值，值可换行）。
class KeyValueRow extends StatelessWidget {
  const KeyValueRow({
    super.key,
    required this.label,
    required this.value,
    this.valueStyle,
    this.monospace = false,
  });

  final String label;
  final String value;
  final TextStyle? valueStyle;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: valueStyle ??
                  theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: monospace ? 'monospace' : null,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 状态标签（已安装 / 可更新 等）。
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

/// 页面内的小节标题。
class SubHeader extends StatelessWidget {
  const SubHeader(this.text, {super.key, this.padding});

  final String text;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// 提示条（信息 / 警告）。
class HintBanner extends StatelessWidget {
  const HintBanner(
    this.text, {
    super.key,
    this.warning = false,
    this.margin = const EdgeInsets.fromLTRB(16, 8, 16, 0),
  });

  final String text;
  final bool warning;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 警告态用 onErrorContainer 而非 error：底色是 errorContainer 的半透明叠加，
    // error 在浅色主题下只有约 4.8:1，onErrorContainer 两种主题都远超 AA。
    final color = warning
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onSurfaceVariant;
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: warning
            ? theme.colorScheme.errorContainer.withValues(alpha: 0.4)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            warning ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// 表单输入行：标题 + 说明 + 输入框。
class FormFieldRow extends StatelessWidget {
  const FormFieldRow({
    super.key,
    required this.label,
    required this.child,
    this.helper,
  });

  final String label;
  final String? helper;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          if (helper != null) ...[
            const SizedBox(height: 2),
            Text(
              helper!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
