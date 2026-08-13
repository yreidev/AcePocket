import 'package:flutter/material.dart';

import '../../../core/widgets/a11y.dart';

import '../models/website_setting.dart';

/// 重定向编辑器，对应 `pkg/webserver/types.Redirect`。
///
/// 类型说明（与面板一致）：
/// - `url`：按路径重定向，来源填 `/old`；
/// - `host`：按域名重定向，来源填 `example.com`；
/// - `404`：404 页面重定向到目标地址。
class RedirectListField extends StatefulWidget {
  const RedirectListField({
    super.key,
    required this.redirects,
    required this.onChanged,
  });

  final List<RedirectConfig> redirects;
  final VoidCallback onChanged;

  @override
  State<RedirectListField> createState() => _RedirectListFieldState();
}

class _RedirectListFieldState extends State<RedirectListField> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.redirects.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              '暂无重定向规则',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final redirect in widget.redirects)
          _RedirectCard(
            key: ObjectKey(redirect),
            redirect: redirect,
            onChanged: widget.onChanged,
            onRemove: () {
              widget.redirects.remove(redirect);
              setState(() {});
              widget.onChanged();
            },
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              widget.redirects.add(
                RedirectConfig(
                  type: 'url',
                  from: '/',
                  to: '',
                  keepUri: true,
                  statusCode: 308,
                ),
              );
              setState(() {});
              widget.onChanged();
            },
            icon: const Icon(Icons.add),
            label: const Text('添加重定向'),
          ),
        ),
      ],
    );
  }
}

class _RedirectCard extends StatefulWidget {
  const _RedirectCard({
    super.key,
    required this.redirect,
    required this.onChanged,
    required this.onRemove,
  });

  final RedirectConfig redirect;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  State<_RedirectCard> createState() => _RedirectCardState();
}

class _RedirectCardState extends State<_RedirectCard> {
  late final TextEditingController _from = TextEditingController(
    text: widget.redirect.from,
  );
  late final TextEditingController _to = TextEditingController(
    text: widget.redirect.to,
  );

  static const _statusCodes = [301, 302, 307, 308];

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = widget.redirect;
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
                  child: DropdownButtonFormField<String>(
                    initialValue: const ['url', 'host', '404'].contains(r.type)
                        ? r.type
                        : 'url',
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '类型'),
                    items: const [
                      DropdownMenuItem(value: 'url', child: Text('路径重定向')),
                      DropdownMenuItem(value: 'host', child: Text('域名重定向')),
                      DropdownMenuItem(value: '404', child: Text('404 重定向')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => r.type = v);
                      widget.onChanged();
                    },
                  ),
                ),
                A11yIconButton(
                  tooltip: r.from.isEmpty ? '删除这条重定向' : '删除重定向 ${r.from}',
                  color: theme.colorScheme.error,
                  onPressed: widget.onRemove,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _from,
                    decoration: InputDecoration(
                      labelText: '来源',
                      hintText: r.type == 'host' ? 'example.com' : '/old',
                    ),
                    onChanged: (v) {
                      r.from = v.trim();
                      widget.onChanged();
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _to,
                    decoration: const InputDecoration(
                      labelText: '目标',
                      hintText: 'https://example.com',
                    ),
                    onChanged: (v) {
                      r.to = v.trim();
                      widget.onChanged();
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _statusCodes.contains(r.statusCode)
                              ? r.statusCode
                              : 308,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: '状态码'),
                          items: [
                            for (final code in _statusCodes)
                              DropdownMenuItem(
                                value: code,
                                child: Text('$code'),
                              ),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => r.statusCode = v);
                            widget.onChanged();
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: const Text('保留 URI'),
                          value: r.keepUri,
                          onChanged: (v) {
                            setState(() => r.keepUri = v);
                            widget.onChanged();
                          },
                        ),
                      ),
                    ],
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
