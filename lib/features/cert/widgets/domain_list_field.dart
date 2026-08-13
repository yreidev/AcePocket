import 'package:flutter/material.dart';

import '../../../core/utils/input_validation.dart';
import '../../../core/widgets/a11y.dart';

/// 域名动态输入框列表（对应面板前端的 n-dynamic-input）。
///
/// 至少保留一行；内容变化时通过 [onChanged] 回传去空后的域名列表。
class DomainListField extends StatefulWidget {
  const DomainListField({
    super.key,
    this.initialDomains = const [],
    required this.onChanged,
    this.label = '域名',
    this.hint = 'example.com',
    this.enabled = true,
  });

  final List<String> initialDomains;
  final ValueChanged<List<String>> onChanged;
  final String label;
  final String hint;
  final bool enabled;

  @override
  State<DomainListField> createState() => _DomainListFieldState();
}

class _DomainListFieldState extends State<DomainListField> {
  final List<TextEditingController> _controllers = [];

  @override
  void initState() {
    super.initState();
    final initial =
        widget.initialDomains.where((e) => e.trim().isNotEmpty).toList();
    if (initial.isEmpty) {
      _controllers.add(TextEditingController());
    } else {
      for (final domain in initial) {
        _controllers.add(TextEditingController(text: domain));
      }
    }
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
    setState(() {
      final controller = _controllers.removeAt(index);
      controller.dispose();
      if (_controllers.isEmpty) {
        _controllers.add(TextEditingController());
      }
    });
    _emit();
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
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (widget.enabled)
              TextButton.icon(
                onPressed: _add,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加'),
              ),
          ],
        ),
        for (var i = 0; i < _controllers.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _controllers[i],
                    enabled: widget.enabled,
                    autocorrect: false,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    decoration: InputDecoration(
                      hintText: widget.hint,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    validator: (value) {
                      final v = (value ?? '').trim();
                      if (v.isEmpty) return null;
                      return validateDomain(v);
                    },
                    onChanged: (_) => _emit(),
                  ),
                ),
                if (widget.enabled)
                  A11yIconButton(
                    tooltip: '删除第 ${i + 1} 个${widget.label}',
                    onPressed:
                        _controllers.length == 1 && _controllers[i].text.isEmpty
                            ? null
                            : () => _removeAt(i),
                    icon: Icon(
                      Icons.remove_circle_outline,
                      color: theme.colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
