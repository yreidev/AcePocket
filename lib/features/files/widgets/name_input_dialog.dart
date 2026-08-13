import 'package:flutter/material.dart';

/// 通用「输入文本」对话框（新建文件 / 新建目录 / 重命名 / 输入路径）。
///
/// 返回用户输入的字符串；取消时返回 null。
Future<String?> showNameInputDialog(
  BuildContext context, {
  required String title,
  String initialValue = '',
  String label = '名称',
  String? helperText,
  String confirmText = '确定',
  bool selectBaseName = false,
  String? Function(String value)? validator,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _NameInputDialog(
      title: title,
      initialValue: initialValue,
      label: label,
      helperText: helperText,
      confirmText: confirmText,
      selectBaseName: selectBaseName,
      validator: validator,
    ),
  );
}

class _NameInputDialog extends StatefulWidget {
  const _NameInputDialog({
    required this.title,
    required this.initialValue,
    required this.label,
    required this.helperText,
    required this.confirmText,
    required this.selectBaseName,
    required this.validator,
  });

  final String title;
  final String initialValue;
  final String label;
  final String? helperText;
  final String confirmText;

  /// 重命名时默认只选中「主文件名」部分（不含扩展名），便于快速修改。
  final bool selectBaseName;

  final String? Function(String value)? validator;

  @override
  State<_NameInputDialog> createState() => _NameInputDialogState();
}

class _NameInputDialogState extends State<_NameInputDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    final value = widget.initialValue;
    final dotIndex = value.lastIndexOf('.');
    final end = widget.selectBaseName && dotIndex > 0 ? dotIndex : value.length;
    _controller.selection = TextSelection(baseOffset: 0, extentOffset: end);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() => _error = '不能为空');
      return;
    }
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
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        decoration: InputDecoration(
          labelText: widget.label,
          helperText: widget.helperText,
          helperMaxLines: 3,
          errorText: _error,
        ),
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
