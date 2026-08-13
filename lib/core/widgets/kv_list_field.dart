import 'package:flutter/material.dart';

import 'a11y.dart';

/// 键值对编辑器。
///
/// 内部以有序列表维护键值，避免编辑过程中 Map 键冲突导致输入丢失；
/// 变更时通过 [onChanged] 回传去掉空键后的 Map。
class KeyValueListField extends StatefulWidget {
  const KeyValueListField({
    super.key,
    required this.label,
    required this.initialValues,
    required this.onChanged,
    this.keyHint = '键',
    this.valueHint = '值',
    this.addButtonText = '添加',
    this.obscureValue = false,
    this.helperText,
  });

  final String label;
  final Map<String, String> initialValues;
  final ValueChanged<Map<String, String>> onChanged;
  final String keyHint;
  final String valueHint;
  final String addButtonText;
  final bool obscureValue;
  final String? helperText;

  @override
  State<KeyValueListField> createState() => _KeyValueListFieldState();
}

class _KeyValueEntry {
  _KeyValueEntry(String key, String value)
    : keyController = TextEditingController(text: key),
      valueController = TextEditingController(text: value);

  final TextEditingController keyController;
  final TextEditingController valueController;

  void dispose() {
    keyController.dispose();
    valueController.dispose();
  }
}

class _KeyValueListFieldState extends State<KeyValueListField> {
  late List<_KeyValueEntry> _entries;
  late bool _obscure;

  @override
  void initState() {
    super.initState();
    _obscure = widget.obscureValue;
    _entries = widget.initialValues.entries
        .map((e) => _KeyValueEntry(e.key, e.value))
        .toList();
  }

  @override
  void dispose() {
    for (final e in _entries) {
      e.dispose();
    }
    super.dispose();
  }

  void _emit() {
    final map = <String, String>{};
    for (final e in _entries) {
      final key = e.keyController.text.trim();
      if (key.isEmpty) continue;
      map[key] = e.valueController.text;
    }
    widget.onChanged(map);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(widget.label, style: theme.textTheme.titleSmall),
            ),
            if (widget.obscureValue)
              A11yIconButton(
                tooltip: _obscure
                    ? '显示${widget.valueHint}'
                    : '隐藏${widget.valueHint}',
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                ),
              ),
          ],
        ),
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
        for (var i = 0; i < _entries.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  flex: 4,
                  child: TextField(
                    controller: _entries[i].keyController,
                    decoration: InputDecoration(hintText: widget.keyHint),
                    onChanged: (_) => _emit(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 5,
                  child: TextField(
                    controller: _entries[i].valueController,
                    obscureText: widget.obscureValue && _obscure,
                    decoration: InputDecoration(hintText: widget.valueHint),
                    onChanged: (_) => _emit(),
                  ),
                ),
                A11yIconButton(
                  tooltip: '删除第 ${i + 1} 条${widget.label}',
                  color: theme.colorScheme.error,
                  onPressed: () {
                    final removed = _entries.removeAt(i);
                    removed.dispose();
                    setState(() {});
                    _emit();
                  },
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              setState(() => _entries.add(_KeyValueEntry('', '')));
              _emit();
            },
            icon: const Icon(Icons.add),
            label: Text(widget.addButtonText),
          ),
        ),
      ],
    );
  }
}
