import 'package:flutter/material.dart';

import '../../../core/utils/input_validation.dart';
import '../../../core/widgets/a11y.dart';
import '../models/website_setting.dart';

/// 监听地址编辑器，对应 `pkg/webserver/types.Listen`。
///
/// 每条监听由「地址 + 参数」组成，HTTPS 对应 `ssl` 参数，
/// QUIC(HTTP/3) 对应 `quic` 参数（仅 nginx 支持）。
/// 直接在传入的 [ListenConfig] 实例上修改，并在增删时调用 [onChanged]。
class ListenListField extends StatefulWidget {
  const ListenListField({
    super.key,
    required this.listens,
    required this.onChanged,
    this.showQuic = true,
  });

  /// 直接编辑的监听列表（调用方持有的可变列表）。
  final List<ListenConfig> listens;

  /// 列表结构或内容变化后的回调（用于父级 setState / 标记为已修改）。
  final VoidCallback onChanged;

  /// 是否展示 QUIC 开关（Web 服务器为 nginx 时才有意义）。
  final bool showQuic;

  @override
  State<ListenListField> createState() => _ListenListFieldState();
}

class _ListenListFieldState extends State<ListenListField> {
  final Map<ListenConfig, TextEditingController> _controllers = {};

  TextEditingController _controllerFor(ListenConfig listen) => _controllers
      .putIfAbsent(listen, () => TextEditingController(text: listen.address));

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('监听地址', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          '如 80、0.0.0.0:80、[::]:443；开启 HTTPS 的监听需配合证书使用',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        for (final listen in widget.listens)
          Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 8),
            color: theme.colorScheme.surfaceContainerHighest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _controllerFor(listen),
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          decoration: const InputDecoration(
                            labelText: '地址',
                            hintText: '80',
                          ),
                          validator: (value) =>
                              validateListenAddress(value ?? ''),
                          onChanged: (v) {
                            listen.address = v.trim();
                            widget.onChanged();
                          },
                        ),
                      ),
                      A11yIconButton(
                        tooltip: listen.address.isEmpty
                            ? '删除这条监听'
                            : '删除监听 ${listen.address}',
                        color: theme.colorScheme.error,
                        onPressed: () {
                          final controller = _controllers.remove(listen);
                          controller?.dispose();
                          widget.listens.remove(listen);
                          setState(() {});
                          widget.onChanged();
                        },
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: const Text('HTTPS'),
                          value: listen.https,
                          onChanged: (v) {
                            setState(() => listen.https = v ?? false);
                            widget.onChanged();
                          },
                        ),
                      ),
                      if (widget.showQuic)
                        Expanded(
                          child: CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: const Text('QUIC'),
                            value: listen.quic,
                            onChanged: (v) {
                              setState(() => listen.quic = v ?? false);
                              widget.onChanged();
                            },
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              widget.listens.add(ListenConfig(address: ''));
              setState(() {});
              widget.onChanged();
            },
            icon: const Icon(Icons.add),
            label: const Text('添加监听'),
          ),
        ),
      ],
    );
  }
}
