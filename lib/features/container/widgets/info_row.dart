library;

export '../../../core/widgets/info_row.dart';

import 'package:flutter/material.dart';

/// 一组标签样式的小块（端口、子网、镜像 tag 等）。
class TagWrap extends StatelessWidget {
  const TagWrap({
    super.key,
    required this.values,
    this.emptyText = '-',
    this.mono = true,
  });

  final List<String> values;
  final String emptyText;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (values.isEmpty) {
      return Text(emptyText, style: theme.textTheme.bodyMedium);
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: values
          .map(
            (value) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                value,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFamily: mono ? 'monospace' : null,
                  fontFamilyFallback: mono ? const ['Courier'] : null,
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

/// 等宽多行文本块（环境变量、原始 JSON 等）。
class MonoBlock extends StatelessWidget {
  const MonoBlock({
    super.key,
    required this.text,
    this.maxHeight,
    this.selectable = true,
  });

  final String text;
  final double? maxHeight;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Courier'],
      height: 1.5,
      color: theme.colorScheme.onSurface,
    );
    final child = selectable
        ? SelectableText(text, style: style)
        : Text(text, style: style);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      constraints:
          maxHeight == null ? null : BoxConstraints(maxHeight: maxHeight!),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: maxHeight == null
          ? child
          : SingleChildScrollView(
              child: SizedBox(width: double.infinity, child: child),
            ),
    );
  }
}
