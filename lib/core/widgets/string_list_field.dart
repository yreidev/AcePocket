import 'package:flutter/material.dart';

import 'a11y.dart';

/// 可增删的字符串列表编辑器。
///
/// 内部维护 [TextEditingController]，变更通过 [onChanged] 回传去空后的列表。
class StringListField extends StatefulWidget {
  // 别名参数（hint / helper / addLabel）无法在 const 构造里折叠，
  // 调用方仍应尽量用 const 子节点；本组件本身因控制器而不能 const。
  // ignore: prefer_const_constructors_in_immutables
  StringListField({
    super.key,
    required this.label,
    required this.initialValues,
    required this.onChanged,
    String? hintText,
    String? hint,
    this.addButtonText = '添加',
    String? addLabel,
    this.minItems = 0,
    this.keyboardType,
    String? helperText,
    String? helper,
    this.itemPrefixIcon,
    this.validator,
  })  : hintText = hintText ?? hint,
        helperText = helperText ?? helper,
        addLabelText = addLabel ?? addButtonText;

  final String label;
  final List<String> initialValues;
  final ValueChanged<List<String>> onChanged;
  final String? hintText;
  final String addButtonText;
  final String addLabelText;
  final int minItems;
  final TextInputType? keyboardType;
  final String? helperText;
  final IconData? itemPrefixIcon;
  final String? Function(String value)? validator;

  @override
  State<StringListField> createState() => _StringListFieldState();
}

class _StringListFieldState extends State<StringListField> {
  late List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    final values = List<String>.from(widget.initialValues);
    while (values.length < widget.minItems) {
      values.add('');
    }
    _controllers = values.map((v) => TextEditingController(text: v)).toList();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _emit() {
    widget.onChanged(_controllers
        .map((c) => c.text.trim())
        .where((e) => e.isNotEmpty)
        .toList());
  }

  void _add() {
    setState(() => _controllers.add(TextEditingController()));
    _emit();
  }

  void _removeAt(int index) {
    if (_controllers.length <= widget.minItems) return;
    final controller = _controllers.removeAt(index);
    controller.dispose();
    setState(() {});
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.label, style: theme.textTheme.titleSmall),
        if (widget.helperText != null) ...[
          const SizedBox(height: 4),
          Text(
            widget.helperText!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 8),
        for (var i = 0; i < _controllers.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _controllers[i],
                    keyboardType: widget.keyboardType,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    decoration: InputDecoration(
                      hintText: widget.hintText,
                      prefixIcon: widget.itemPrefixIcon == null
                          ? null
                          : Icon(widget.itemPrefixIcon, size: 18),
                    ),
                    validator: widget.validator == null
                        ? null
                        : (value) {
                            final v = (value ?? '').trim();
                            if (v.isEmpty) return null;
                            return widget.validator!(v);
                          },
                    onChanged: (_) => _emit(),
                  ),
                ),
                A11yIconButton(
                  tooltip: '删除第 ${i + 1} 条${widget.label}',
                  onPressed: _controllers.length <= widget.minItems
                      ? null
                      : () => _removeAt(i),
                  icon: const Icon(Icons.remove_circle_outline),
                  color: theme.colorScheme.error,
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _add,
            icon: const Icon(Icons.add),
            label: Text(widget.addLabelText),
          ),
        ),
      ],
    );
  }
}
