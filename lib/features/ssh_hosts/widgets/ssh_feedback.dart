/// SSH 主机模块的通用交互组件。
///
/// 提示统一走 core 的 `app_snack.dart`（配色成对取自 ColorScheme，
/// 深浅主题对比度均达标），本文件只保留模块自用的文本输入对话框。
library;

import 'package:flutter/material.dart';

/// 通用文本输入对话框，返回用户输入（取消返回 null）。
///
/// 输入为空时不再「按了没反应」，而是在输入框下方给出 [emptyError] 提示。
Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  String initialValue = '',
  String? label,
  String? hintText,
  String? helperText,
  String confirmText = '确定',
  String emptyError = '请输入内容',
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _TextInputDialog(
      title: title,
      initialValue: initialValue,
      label: label,
      hintText: hintText,
      helperText: helperText,
      confirmText: confirmText,
      emptyError: emptyError,
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
    required this.confirmText,
    required this.emptyError,
  });

  final String title;
  final String initialValue;
  final String? label;
  final String? hintText;
  final String? helperText;
  final String confirmText;
  final String emptyError;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _error = widget.emptyError);
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hintText,
          helperText: widget.helperText,
          // 目录路径可能很长，helperText 默认只有一行会被截断。
          helperMaxLines: 3,
          errorText: _error,
          errorMaxLines: 2,
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
