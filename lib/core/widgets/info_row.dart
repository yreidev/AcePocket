import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_snack.dart';

/// 「标签 — 值」信息行。
class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.monospace = false,
    this.mono = false,
    this.copyable = false,
    this.selectable = false,
    this.valueWidget,
    this.emptyPlaceholder = '—',
    this.labelWidth = 92,
  });

  final String label;
  final String value;
  final Color? valueColor;

  /// 值是否使用等宽字体。
  final bool monospace;

  /// [monospace] 的历史别名（容器模块）。
  final bool mono;

  /// 点击 / 长按复制 [value]。
  final bool copyable;

  /// 值是否可选择复制（磁盘等长路径场景）。
  final bool selectable;

  /// 自定义值组件（提供时忽略 [value] 的文本渲染）。
  final Widget? valueWidget;

  final String emptyPlaceholder;

  /// 左侧标签固定宽度。
  final double labelWidth;

  bool get _mono => monospace || mono;

  String get _display => value.isEmpty ? emptyPlaceholder : value;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    showSuccessSnack(context, '已复制$label');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: valueColor ?? theme.colorScheme.onSurface,
      fontFamily: _mono ? 'monospace' : null,
      fontFamilyFallback: _mono ? const ['Courier'] : null,
    );
    final content = valueWidget ??
        (selectable
            ? SelectableText(
                _display,
                textAlign: TextAlign.right,
                style: style,
              )
            : Text(
                _display,
                textAlign: TextAlign.right,
                style: style,
              ));

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: content),
          if (copyable && value.isNotEmpty && valueWidget == null) ...[
            const SizedBox(width: 8),
            Icon(
              Icons.copy_outlined,
              size: 16,
              color: theme.colorScheme.outline,
            ),
          ],
        ],
      ),
    );

    if (!copyable || value.isEmpty || valueWidget != null) return row;

    return Semantics(
      onLongPressHint: '复制$label',
      button: true,
      child: InkWell(
        onTap: () => _copy(context),
        onLongPress: () => _copy(context),
        child: row,
      ),
    );
  }
}
