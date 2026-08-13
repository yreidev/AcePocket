import 'package:flutter/material.dart';

import '../../../core/widgets/a11y.dart';

/// DNS 验证别名映射输入（原域名 → 别名记录）。
///
/// 对应面板 `request.CertCreate.Alias`（`map[string]string`）：
/// 把 `example.com` 的 `_acme-challenge` 记录委派到另一个域名下时使用。
class AliasListField extends StatefulWidget {
  const AliasListField({
    super.key,
    this.initialAlias = const {},
    required this.onChanged,
  });

  final Map<String, String> initialAlias;
  final ValueChanged<Map<String, String>> onChanged;

  @override
  State<AliasListField> createState() => _AliasListFieldState();
}

class _AliasEntry {
  _AliasEntry({String key = '', String value = ''})
    : keyController = TextEditingController(text: key),
      valueController = TextEditingController(text: value);

  final TextEditingController keyController;
  final TextEditingController valueController;

  void dispose() {
    keyController.dispose();
    valueController.dispose();
  }
}

class _AliasListFieldState extends State<AliasListField> {
  final List<_AliasEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    widget.initialAlias.forEach((key, value) {
      _entries.add(_AliasEntry(key: key, value: value));
    });
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
      final value = e.valueController.text.trim();
      if (key.isNotEmpty && value.isNotEmpty) {
        map[key] = value;
      }
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
              child: Text(
                'DNS 验证别名（可选）',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () {
                setState(() => _entries.add(_AliasEntry()));
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加'),
            ),
          ],
        ),
        if (_entries.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '把 _acme-challenge 记录委派到其他域名时填写',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (var i = 0; i < _entries.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _entries[i].keyController,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      hintText: 'example.com',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => _emit(),
                  ),
                ),
                // 纯装饰的方向箭头，语义上由「原域名 → 别名」两个输入框自述。
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: ExcludeSemantics(
                    child: Icon(Icons.arrow_forward, size: 18),
                  ),
                ),
                Expanded(
                  child: TextFormField(
                    controller: _entries[i].valueController,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      hintText: '_acme-challenge.other.com',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => _emit(),
                  ),
                ),
                A11yIconButton(
                  tooltip: '删除第 ${i + 1} 条别名映射',
                  onPressed: () {
                    setState(() {
                      final entry = _entries.removeAt(i);
                      entry.dispose();
                    });
                    _emit();
                  },
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
