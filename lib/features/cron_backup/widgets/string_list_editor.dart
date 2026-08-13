import 'package:flutter/material.dart';

import '../../../core/widgets/a11y.dart';

/// 字符串列表编辑器（用于「备份目录」这类需要手动输入多个值的字段）。
///
/// 每行的身份由它自己的 [TextEditingController] 承载，而不是下标：
/// 早先的实现是 `StatelessWidget` + `TextFormField(key: ValueKey('...-$i'),
/// initialValue: values[i])`，删除某一行后父级重建，Flutter 按下标复用了旧
/// Element，`initialValue` 只在首次创建时生效，界面上仍显示被删掉那行的文字，
/// 而实际提交的是后一行的值（`['/a','/b']` 删掉 `/a` 后仍显示 `/a`，
/// 实际备份的却是 `/b`）。改为受控 controller 后，显示内容永远等于数据本身。
class StringListEditor extends StatefulWidget {
  const StringListEditor({
    super.key,
    required this.label,
    required this.values,
    required this.onChanged,
    this.hintText = '',
    this.addLabel = '添加',
  });

  final String label;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  final String hintText;
  final String addLabel;

  @override
  State<StringListEditor> createState() => _StringListEditorState();
}

class _StringListEditorState extends State<StringListEditor> {
  /// 每行一个控制器；控制器实例本身就是该行的稳定身份（用作 Widget key）。
  final List<TextEditingController> _controllers = [];

  @override
  void initState() {
    super.initState();
    _syncFromValues();
  }

  @override
  void didUpdateWidget(covariant StringListEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 只有外部把值换成了与当前输入框不一致的内容（如切换备份类型后清空目标）
    // 才重建控制器；自己触发的增删改回流到这里时内容已经一致，直接跳过，
    // 避免重置光标位置与输入法状态。
    // 紧接着就会重建，不必再 setState。
    if (!_matchesValues()) _syncFromValues();
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  bool _matchesValues() {
    if (_controllers.length != widget.values.length) return false;
    for (var i = 0; i < _controllers.length; i++) {
      if (_controllers[i].text != widget.values[i]) return false;
    }
    return true;
  }

  void _syncFromValues() {
    final values = widget.values;
    while (_controllers.length > values.length) {
      _controllers.removeLast().dispose();
    }
    for (var i = 0; i < values.length; i++) {
      if (i < _controllers.length) {
        if (_controllers[i].text != values[i]) _controllers[i].text = values[i];
      } else {
        _controllers.add(TextEditingController(text: values[i]));
      }
    }
  }

  List<String> get _currentValues =>
      _controllers.map((c) => c.text).toList(growable: false);

  void _add() {
    setState(() => _controllers.add(TextEditingController()));
    widget.onChanged(_currentValues);
  }

  void _removeAt(int index) {
    setState(() => _controllers.removeAt(index).dispose());
    widget.onChanged(_currentValues);
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
              child: Text(
                widget.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.add, size: 18),
              label: Text(widget.addLabel),
            ),
          ],
        ),
        if (_controllers.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '尚未添加，点击右上角的「${widget.addLabel}」新增一行',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (var i = 0; i < _controllers.length; i++)
          Padding(
            key: ObjectKey(_controllers[i]),
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _controllers[i],
                    autocorrect: false,
                    decoration: InputDecoration(hintText: widget.hintText),
                    onChanged: (_) => widget.onChanged(_currentValues),
                  ),
                ),
                A11yIconButton(
                  tooltip: '移除第 ${i + 1} 行${widget.label}',
                  icon: Icon(
                    Icons.remove_circle_outline,
                    color: theme.colorScheme.error,
                  ),
                  onPressed: () => _removeAt(i),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
