import 'package:flutter/material.dart';

import 'format.dart';

/// 周期（crontab 表达式）输入组件。
///
/// - 直接输入 5 段表达式，实时中文预览；
/// - 「常用周期」快速填充；
/// - 「分段设置」逐字段编辑（分 / 时 / 日 / 月 / 周）。
class CronExpressionField extends StatelessWidget {
  const CronExpressionField({
    super.key,
    required this.controller,
    this.enabled = true,
  });

  final TextEditingController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: controller,
          enabled: enabled,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: '执行周期（crontab 表达式）',
            hintText: '*/30 * * * *',
            helperText: '格式：分 时 日 月 周',
            suffixIcon: IconButton(
              tooltip: '分段设置',
              icon: const Icon(Icons.tune),
              onPressed: enabled ? () => _openBuilder(context) : null,
            ),
          ),
          validator: (value) {
            final text = (value ?? '').trim();
            if (text.isEmpty) return '请填写执行周期';
            if (!isValidCronExpression(text)) {
              return '表达式格式不正确，应为 5 段（分 时 日 月 周）';
            }
            return null;
          },
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            return Row(
              children: [
                Icon(Icons.schedule,
                    size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    describeCron(value.text),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final preset in kCronPresets)
              ActionChip(
                label: Text(preset.label),
                onPressed:
                    enabled ? () => controller.text = preset.expression : null,
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _openBuilder(BuildContext context) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _CronBuilderSheet(expression: controller.text),
    );
    if (result != null && result.isNotEmpty) {
      controller.text = result;
    }
  }
}

class _CronBuilderSheet extends StatefulWidget {
  const _CronBuilderSheet({required this.expression});

  final String expression;

  @override
  State<_CronBuilderSheet> createState() => _CronBuilderSheetState();
}

class _CronBuilderSheetState extends State<_CronBuilderSheet> {
  late final List<TextEditingController> _controllers;

  static const _labels = ['分钟', '小时', '日', '月', '星期'];
  static const _hints = ['0-59', '0-23', '1-31', '1-12', '0-6（0 为周日）'];

  @override
  void initState() {
    super.initState();
    final fields = widget.expression.trim().split(RegExp(r'\s+'));
    _controllers = List.generate(
      5,
      (i) => TextEditingController(
        text: fields.length == 5 ? fields[i] : '*',
      ),
    );
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  String get _expression => _controllers
      .map((c) => c.text.trim().isEmpty ? '*' : c.text.trim())
      .join(' ');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('分段设置执行周期', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '每段可填 * （任意）、数字、*/n（每 n）、1,3（枚举）、1-5（区间）',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < 5; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: _controllers[i],
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: _labels[i],
                    hintText: _hints[i],
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    _expression,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    describeCron(_expression),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: isValidCronExpression(_expression)
                        ? () => Navigator.of(context).pop(_expression)
                        : null,
                    child: const Text('使用'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
