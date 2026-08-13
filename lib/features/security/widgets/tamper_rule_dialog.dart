import 'package:flutter/material.dart';

import '../models/tamper_models.dart';

/// 新建 / 编辑防篡改保护规则。
///
/// [rule] 为空表示新建；编辑时标识（name）不可修改（面板更新接口不支持）。
Future<TamperRuleDraft?> showTamperRuleSheet(
  BuildContext context, {
  TamperRule? rule,
}) {
  return showModalBottomSheet<TamperRuleDraft>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: _TamperRuleForm(rule: rule),
        ),
      ),
    ),
  );
}

class _TamperRuleForm extends StatefulWidget {
  const _TamperRuleForm({this.rule});

  final TamperRule? rule;

  @override
  State<_TamperRuleForm> createState() => _TamperRuleFormState();
}

class _TamperRuleFormState extends State<_TamperRuleForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _name = TextEditingController(
    text: widget.rule?.name ?? '',
  );
  late final TextEditingController _path = TextEditingController(
    text: widget.rule?.path ?? '',
  );
  late final TextEditingController _exts = TextEditingController(
    text: (widget.rule?.exts ?? const []).join(', '),
  );
  late final TextEditingController _excludes = TextEditingController(
    text: (widget.rule?.excludes ?? const []).join(', '),
  );

  late bool _enabled = widget.rule?.enabled ?? true;

  bool get _isEdit => widget.rule != null;

  @override
  void dispose() {
    _name.dispose();
    _path.dispose();
    _exts.dispose();
    _excludes.dispose();
    super.dispose();
  }

  /// 逗号 / 空白分隔的输入转为列表（后缀自动去掉前导点）。
  static List<String> _split(String raw, {bool stripDot = false}) {
    return raw
        .split(RegExp(r'[,，\s]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .map((e) => stripDot && e.startsWith('.') ? e.substring(1) : e)
        .toList();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      TamperRuleDraft(
        name: _name.text.trim(),
        path: _path.text.trim(),
        exts: _split(_exts.text, stripDot: true),
        excludes: _split(_excludes.text),
        enabled: _enabled,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _isEdit ? '编辑保护规则' : '新建保护规则',
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _name,
            enabled: !_isEdit,
            decoration: InputDecoration(
              labelText: '标识',
              hintText: '如 example.com',
              helperText: _isEdit ? '标识创建后不可修改' : '规则的唯一标识，通常填网站名',
              border: const OutlineInputBorder(),
            ),
            validator: (value) {
              if (_isEdit) return null;
              return (value ?? '').trim().isEmpty ? '请输入规则标识' : null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _path,
            decoration: const InputDecoration(
              labelText: '受保护目录',
              hintText: '/www/wwwroot/example.com',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              final text = (value ?? '').trim();
              if (text.isEmpty) return '请输入受保护目录';
              if (!text.startsWith('/')) return '请输入绝对路径（以 / 开头）';
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _exts,
            decoration: const InputDecoration(
              labelText: '受保护后缀',
              hintText: 'php, js, html',
              helperText: '逗号分隔；留空表示保护全部文件',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _excludes,
            decoration: const InputDecoration(
              labelText: '排除子路径',
              hintText: 'runtime, storage/logs',
              helperText: '逗号分隔；这些子路径不受保护',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _enabled,
            title: const Text('启用该规则'),
            onChanged: (value) => setState(() => _enabled = value),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _submit, child: Text(_isEdit ? '保存' : '创建')),
        ],
      ),
    );
  }
}
