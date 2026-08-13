import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/app_snack.dart';

export '../../../core/widgets/info_row.dart';

/// 表单文本输入项（带标题与可选说明）。
class SettingTextField extends StatelessWidget {
  const SettingTextField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.helper,
    this.keyboardType,
    this.inputFormatters,
    this.maxLines = 1,
    this.enabled = true,
    this.validator,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? helper;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int maxLines;
  final bool enabled;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        maxLines: maxLines,
        minLines: 1,
        validator: validator,
        onChanged: onChanged,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helper,
          helperMaxLines: 3,
        ),
      ),
    );
  }
}

/// 表单下拉选择项。
class SettingDropdown<T> extends StatelessWidget {
  const SettingDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.helper,
  });

  final String label;
  final T value;

  /// 选项：值 -> 显示文本。
  final Map<T, String> items;
  final ValueChanged<T> onChanged;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<T>(
        initialValue: items.containsKey(value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 3,
        ),
        items: items.entries
            .map((e) => DropdownMenuItem<T>(
                  value: e.key,
                  child: Text(e.value, overflow: TextOverflow.ellipsis),
                ))
            .toList(),
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

/// 表单开关项。
class SettingSwitchTile extends StatelessWidget {
  const SettingSwitchTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title, style: theme.textTheme.bodyLarge),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}

/// 字符串列表编辑器（绑定域名 / IP 白名单 / 公网 IP 等）。
///
/// 以 Chip 展示已有条目，输入框回车或点击「添加」新增，Chip 上的叉号删除。
/// 与 core 行式列表（`lib/core/widgets/string_list_field.dart`）不同，短条目更适合 Chip。
class StringListField extends StatefulWidget {
  const StringListField({
    super.key,
    required this.label,
    required this.values,
    required this.onChanged,
    this.hint,
    this.helper,
  });

  final String label;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  final String? hint;
  final String? helper;

  @override
  State<StringListField> createState() => _StringListFieldState();
}

class _StringListFieldState extends State<StringListField> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    if (widget.values.contains(text)) {
      // 静默清空输入框会让用户以为没添加成功，明确说明重复。
      showInfoSnack(context, '「$text」已在${widget.label}列表中');
      _controller.clear();
      return;
    }
    widget.onChanged([...widget.values, text]);
    _controller.clear();
  }

  void _remove(String value) {
    widget.onChanged(widget.values.where((e) => e != value).toList());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _add(),
                  decoration: InputDecoration(
                    labelText: widget.label,
                    hintText: widget.hint,
                    helperText: widget.helper,
                    helperMaxLines: 3,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: IconButton.filledTonal(
                  onPressed: _add,
                  icon: const Icon(Icons.add),
                  tooltip: '添加到${widget.label}列表',
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                ),
              ),
            ],
          ),
          if (widget.values.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: widget.values
                  .map(
                    (v) => Chip(
                      // 绑定 UA 之类的值可能很长，限宽省略避免撑破布局。
                      label: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: Text(
                          v,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      labelStyle: theme.textTheme.bodySmall,
                      onDeleted: () => _remove(v),
                      deleteButtonTooltipMessage: '移除 $v',
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}
