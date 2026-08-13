import 'package:flutter/material.dart';

import '../../../core/widgets/a11y.dart';

import '../models/website_setting.dart';

/// 自定义配置片段编辑器，对应 `request.WebsiteCustomConfig`。
///
/// - 名称仅允许字母数字与 `-` `_`（面板校验规则）；
/// - 作用域 `site` 表示仅本网站，`shared` 表示全局共享。
class CustomConfigListField extends StatefulWidget {
  const CustomConfigListField({
    super.key,
    required this.configs,
    required this.onChanged,
  });

  final List<CustomConfig> configs;
  final VoidCallback onChanged;

  @override
  State<CustomConfigListField> createState() => _CustomConfigListFieldState();
}

class _CustomConfigListFieldState extends State<CustomConfigListField> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '自定义配置会被写入网站配置目录并在保存时校验，语法错误会导致保存失败',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        if (widget.configs.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '暂无自定义配置',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final config in widget.configs)
          _CustomConfigCard(
            key: ObjectKey(config),
            config: config,
            onChanged: widget.onChanged,
            onRemove: () {
              widget.configs.remove(config);
              setState(() {});
              widget.onChanged();
            },
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              widget.configs.add(
                CustomConfig(name: '', scope: 'site', content: ''),
              );
              setState(() {});
              widget.onChanged();
            },
            icon: const Icon(Icons.add),
            label: const Text('添加配置'),
          ),
        ),
      ],
    );
  }
}

class _CustomConfigCard extends StatefulWidget {
  const _CustomConfigCard({
    super.key,
    required this.config,
    required this.onChanged,
    required this.onRemove,
  });

  final CustomConfig config;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  State<_CustomConfigCard> createState() => _CustomConfigCardState();
}

class _CustomConfigCardState extends State<_CustomConfigCard> {
  late final TextEditingController _name = TextEditingController(
    text: widget.config.name,
  );
  late final TextEditingController _content = TextEditingController(
    text: widget.config.content,
  );

  @override
  void dispose() {
    _name.dispose();
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = widget.config;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _name,
                    decoration: const InputDecoration(
                      labelText: '名称',
                      hintText: 'custom',
                    ),
                    onChanged: (v) {
                      c.name = v.trim();
                      widget.onChanged();
                    },
                  ),
                ),
                A11yIconButton(
                  tooltip: c.name.isEmpty ? '删除这段自定义配置' : '删除自定义配置 ${c.name}',
                  color: theme.colorScheme.error,
                  onPressed: widget.onRemove,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: c.scope == 'shared' ? 'shared' : 'site',
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '作用域'),
                    items: const [
                      DropdownMenuItem(value: 'site', child: Text('仅本网站')),
                      DropdownMenuItem(value: 'shared', child: Text('全局共享')),
                    ],
                    onChanged: (v) {
                      setState(() => c.scope = v ?? 'site');
                      widget.onChanged();
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _content,
                    maxLines: 8,
                    minLines: 4,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                    decoration: const InputDecoration(
                      labelText: '配置内容',
                      alignLabelWithHint: true,
                    ),
                    onChanged: (v) {
                      c.content = v;
                      widget.onChanged();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
