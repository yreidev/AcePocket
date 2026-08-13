import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/app_snack.dart';

// 提示与异常文案统一走 core：
// - `showErrorSnack` / `showSuccessSnack` / `showInfoSnack`（core/widgets/app_snack.dart）
// - `describeError`（core/api/api_exception.dart）
// 本文件曾自带一份 showSnack / errorMessage，与 core 的实现重复且配色更差，已删除。

/// 通用文本输入对话框，返回用户输入（取消返回 null）。
Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  String initialValue = '',
  String? label,
  String? hintText,
  String? helperText,
  bool obscureText = false,
  TextInputType keyboardType = TextInputType.text,
  List<TextInputFormatter>? inputFormatters,
  String confirmText = '保存',
  int maxLines = 1,
  String? Function(String value)? validator,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _TextInputDialog(
      title: title,
      initialValue: initialValue,
      label: label,
      hintText: hintText,
      helperText: helperText,
      obscureText: obscureText,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      confirmText: confirmText,
      maxLines: maxLines,
      validator: validator,
    ),
  );
}

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.initialValue,
    required this.label,
    required this.hintText,
    required this.helperText,
    required this.obscureText,
    required this.keyboardType,
    required this.inputFormatters,
    required this.confirmText,
    required this.maxLines,
    required this.validator,
  });

  final String title;
  final String initialValue;
  final String? label;
  final String? hintText;
  final String? helperText;
  final bool obscureText;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String confirmText;
  final int maxLines;
  final String? Function(String value)? validator;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    final error = widget.validator?.call(value);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: widget.obscureText,
        keyboardType: widget.keyboardType,
        inputFormatters: widget.inputFormatters,
        maxLines: widget.obscureText ? 1 : widget.maxLines,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hintText,
          helperText: widget.helperText,
          helperMaxLines: 3,
          errorText: _error,
          errorMaxLines: 3,
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmText)),
      ],
    );
  }
}

/// 整数输入对话框（端口、天数、阈值等），返回 null 表示取消或输入非法。
Future<int?> showIntInputDialog(
  BuildContext context, {
  required String title,
  required int initialValue,
  required int min,
  required int max,
  String? label,
  String? helperText,
  String confirmText = '保存',
}) async {
  final text = await showTextInputDialog(
    context,
    title: title,
    initialValue: '$initialValue',
    label: label,
    helperText: helperText,
    confirmText: confirmText,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    validator: (value) {
      final number = int.tryParse(value);
      if (number == null) return '请输入数字';
      if (number < min || number > max) return '需在 $min-$max 之间';
      return null;
    },
  );
  if (text == null) return null;
  return int.tryParse(text);
}

/// 单选对话框：从 [options] 中选择一项，返回选中值（取消返回 null）。
Future<T?> showOptionsDialog<T>(
  BuildContext context, {
  required String title,
  required List<T> options,
  required T? value,
  required String Function(T option) labelBuilder,
  String Function(T option)? subtitleBuilder,
}) {
  return showDialog<T>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(title),
      children: [
        // Flutter 3.32+ 用 RadioGroup 管理分组值与变更回调。
        RadioGroup<T>(
          groupValue: value,
          onChanged: (selected) => Navigator.of(context).pop(selected),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final option in options)
                RadioListTile<T>(
                  value: option,
                  title: Text(labelBuilder(option)),
                  subtitle: subtitleBuilder == null
                      ? null
                      : Text(subtitleBuilder(option)),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
          ),
        ),
      ],
    ),
  );
}

/// 密码设置对话框（需两次输入一致），返回密码（取消返回 null）。
Future<String?> showPasswordDialog(
  BuildContext context, {
  required String title,
  String? helperText,
  int minLength = 8,
  String confirmText = '保存',
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _PasswordDialog(
      title: title,
      helperText: helperText,
      minLength: minLength,
      confirmText: confirmText,
    ),
  );
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({
    required this.title,
    required this.helperText,
    required this.minLength,
    required this.confirmText,
  });

  final String title;
  final String? helperText;
  final int minLength;
  final String confirmText;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    final password = _password.text;
    if (password.length < widget.minLength) {
      setState(() => _error = '密码长度至少 ${widget.minLength} 位');
      return;
    }
    if (password != _confirm.text) {
      setState(() => _error = '两次输入的密码不一致');
      return;
    }
    Navigator.of(context).pop(password);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _password,
            obscureText: _obscure,
            autofocus: true,
            decoration: InputDecoration(
              labelText: '新密码',
              helperText: widget.helperText,
              helperMaxLines: 3,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirm,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: '确认密码',
              errorText: _error,
              errorMaxLines: 2,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmText)),
      ],
    );
  }
}

/// 多选对话框：返回选中项集合（取消返回 null）。
Future<List<String>?> showMultiSelectDialog(
  BuildContext context, {
  required String title,
  required List<String> options,
  required List<String> selected,
  String Function(String option)? labelBuilder,
  String? emptyHint,
}) {
  return showDialog<List<String>>(
    context: context,
    builder: (context) => _MultiSelectDialog(
      title: title,
      options: options,
      selected: selected,
      labelBuilder: labelBuilder,
      emptyHint: emptyHint,
    ),
  );
}

class _MultiSelectDialog extends StatefulWidget {
  const _MultiSelectDialog({
    required this.title,
    required this.options,
    required this.selected,
    required this.labelBuilder,
    required this.emptyHint,
  });

  final String title;
  final List<String> options;
  final List<String> selected;
  final String Function(String option)? labelBuilder;
  final String? emptyHint;

  @override
  State<_MultiSelectDialog> createState() => _MultiSelectDialogState();
}

class _MultiSelectDialogState extends State<_MultiSelectDialog> {
  late final Set<String> _selected = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        child: widget.options.isEmpty
            ? Text(
                widget.emptyHint ?? '暂无可选项',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final option in widget.options)
                    CheckboxListTile(
                      value: _selected.contains(option),
                      title: Text(
                        widget.labelBuilder?.call(option) ?? option,
                      ),
                      onChanged: (checked) => setState(() {
                        if (checked ?? false) {
                          _selected.add(option);
                        } else {
                          _selected.remove(option);
                        }
                      }),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selected.toList()),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

/// 字符串列表编辑对话框（域名 / IP / UA / 白名单等）。
///
/// 返回编辑后的列表，取消返回 null。
Future<List<String>?> showStringListEditor(
  BuildContext context, {
  required String title,
  required List<String> values,
  String? hintText,
  String? helperText,
  String? Function(String value)? validator,
}) {
  return showDialog<List<String>>(
    context: context,
    builder: (context) => _StringListEditor(
      title: title,
      values: values,
      hintText: hintText,
      helperText: helperText,
      validator: validator,
    ),
  );
}

class _StringListEditor extends StatefulWidget {
  const _StringListEditor({
    required this.title,
    required this.values,
    required this.hintText,
    required this.helperText,
    required this.validator,
  });

  final String title;
  final List<String> values;
  final String? hintText;
  final String? helperText;
  final String? Function(String value)? validator;

  @override
  State<_StringListEditor> createState() => _StringListEditorState();
}

class _StringListEditorState extends State<_StringListEditor> {
  late final List<String> _values = [...widget.values];
  final TextEditingController _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    if (_values.contains(value)) {
      setState(() => _error = '该项已存在');
      return;
    }
    final error = widget.validator?.call(value);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _values.add(value);
      _controller.clear();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_values.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '暂未添加任何条目（留空表示不限制）',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final value in _values)
                        InputChip(
                          label: Text(value),
                          onDeleted: () =>
                              setState(() => _values.remove(value)),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: widget.hintText,
                helperText: widget.helperText,
                helperMaxLines: 3,
                errorText: _error,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: '添加',
                  onPressed: _add,
                ),
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _add(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_values),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

/// 只读文本展示对话框（如查看私钥），支持一键复制。
Future<void> showTextViewDialog(
  BuildContext context, {
  required String title,
  required String content,
  String? emptyMessage,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      final isEmpty = content.trim().isEmpty;
      return AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: isEmpty
              ? Text(
                  emptyMessage ?? '暂无内容',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      content,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
        ),
        actions: [
          if (!isEmpty)
            TextButton.icon(
              icon: const Icon(Icons.copy_all_outlined),
              label: const Text('复制'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: content));
                if (!context.mounted) return;
                showSuccessSnack(context, '已复制到剪贴板');
              },
            ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      );
    },
  );
}
