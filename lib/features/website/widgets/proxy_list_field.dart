import 'package:flutter/material.dart';

import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/animated_reveal.dart';
import '../models/json_utils.dart';
import '../models/website_setting.dart';
import 'kv_list_field.dart';

/// 非负整数输入校验；[emptyHint] 描述留空 / 0 的含义。
String? _validateNonNegativeInt(String? value, String emptyHint) {
  final v = (value ?? '').trim();
  if (v.isEmpty) return null;
  final n = int.tryParse(v);
  if (n == null || n < 0) return '请输入非负整数，$emptyHint';
  return null;
}

/// 上游服务器编辑器，对应 `pkg/webserver/types.Upstream`。
class UpstreamListField extends StatefulWidget {
  const UpstreamListField({
    super.key,
    required this.upstreams,
    required this.onChanged,
  });

  final List<UpstreamConfig> upstreams;
  final VoidCallback onChanged;

  @override
  State<UpstreamListField> createState() => _UpstreamListFieldState();
}

class _UpstreamListFieldState extends State<UpstreamListField> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '上游用于负载均衡，配置后可在反向代理的「代理地址」中填写 http://上游名称',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        if (widget.upstreams.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '暂无上游服务器',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final upstream in widget.upstreams)
          _UpstreamCard(
            key: ObjectKey(upstream),
            upstream: upstream,
            onChanged: widget.onChanged,
            onRemove: () {
              widget.upstreams.remove(upstream);
              setState(() {});
              widget.onChanged();
            },
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              widget.upstreams.add(
                UpstreamConfig(
                  name: 'backend',
                  servers: {'127.0.0.1:8080': ''},
                  algo: '',
                  keepalive: 0,
                ),
              );
              setState(() {});
              widget.onChanged();
            },
            icon: const Icon(Icons.add),
            label: const Text('添加上游'),
          ),
        ),
      ],
    );
  }
}

class _UpstreamCard extends StatefulWidget {
  const _UpstreamCard({
    super.key,
    required this.upstream,
    required this.onChanged,
    required this.onRemove,
  });

  final UpstreamConfig upstream;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  State<_UpstreamCard> createState() => _UpstreamCardState();
}

class _UpstreamCardState extends State<_UpstreamCard> {
  late final TextEditingController _name = TextEditingController(
    text: widget.upstream.name,
  );
  late final TextEditingController _keepalive = TextEditingController(
    text: '${widget.upstream.keepalive}',
  );

  static const _algos = ['', 'least_conn', 'ip_hash', 'random'];

  @override
  void dispose() {
    _name.dispose();
    _keepalive.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final u = widget.upstream;
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
                      labelText: '上游名称',
                      hintText: 'backend',
                    ),
                    onChanged: (v) {
                      u.name = v.trim();
                      widget.onChanged();
                    },
                  ),
                ),
                A11yIconButton(
                  tooltip: u.name.isEmpty ? '删除这个上游' : '删除上游 ${u.name}',
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
                  KeyValueListField(
                    label: '服务器',
                    initialValues: u.servers,
                    keyHint: '127.0.0.1:8080',
                    valueHint: 'weight=5',
                    addButtonText: '添加服务器',
                    helperText: '左侧为地址，右侧为可选参数（如 weight=5 backup）',
                    onChanged: (v) {
                      u.servers = v;
                      widget.onChanged();
                    },
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _algos.contains(u.algo) ? u.algo : '',
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: '负载均衡算法',
                          ),
                          items: const [
                            DropdownMenuItem(value: '', child: Text('轮询（默认）')),
                            DropdownMenuItem(
                              value: 'least_conn',
                              child: Text('最少连接'),
                            ),
                            DropdownMenuItem(
                              value: 'ip_hash',
                              child: Text('IP 哈希'),
                            ),
                            DropdownMenuItem(
                              value: 'random',
                              child: Text('随机'),
                            ),
                          ],
                          onChanged: (v) {
                            setState(() => u.algo = v ?? '');
                            widget.onChanged();
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _keepalive,
                          keyboardType: TextInputType.number,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          decoration: const InputDecoration(
                            labelText: '保持连接数',
                            hintText: '0',
                          ),
                          validator: (value) =>
                              _validateNonNegativeInt(value, '留空或 0 表示不保持连接'),
                          onChanged: (v) {
                            final t = v.trim();
                            final n = t.isEmpty ? 0 : int.tryParse(t);
                            // 非法输入不写回模型，由 validator 提示用户修正。
                            if (n != null && n >= 0) u.keepalive = n;
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

/// 反向代理编辑器，对应 `pkg/webserver/types.Proxy`。
///
/// 移动端编辑常用字段（匹配路径、代理地址、Host、SNI、缓冲、HTTP 版本、
/// 请求体大小限制、自定义请求头、响应内容替换），其余高级字段
/// （缓存、超时、重试、SSL 后端等）保存在模型的 extra 中原样回传，不会丢失。
class ProxyListField extends StatefulWidget {
  const ProxyListField({
    super.key,
    required this.proxies,
    required this.onChanged,
  });

  final List<ProxyConfig> proxies;
  final VoidCallback onChanged;

  @override
  State<ProxyListField> createState() => _ProxyListFieldState();
}

class _ProxyListFieldState extends State<ProxyListField> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.proxies.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '暂无反向代理规则',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final proxy in widget.proxies)
          _ProxyCard(
            key: ObjectKey(proxy),
            proxy: proxy,
            onChanged: widget.onChanged,
            onRemove: () {
              widget.proxies.remove(proxy);
              setState(() {});
              widget.onChanged();
            },
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              widget.proxies.add(ProxyConfig.newDefault());
              setState(() {});
              widget.onChanged();
            },
            icon: const Icon(Icons.add),
            label: const Text('添加代理'),
          ),
        ),
      ],
    );
  }
}

class _ProxyCard extends StatefulWidget {
  const _ProxyCard({
    super.key,
    required this.proxy,
    required this.onChanged,
    required this.onRemove,
  });

  final ProxyConfig proxy;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  State<_ProxyCard> createState() => _ProxyCardState();
}

class _ProxyCardState extends State<_ProxyCard> {
  late final TextEditingController _location = TextEditingController(
    text: widget.proxy.location,
  );
  late final TextEditingController _pass = TextEditingController(
    text: widget.proxy.pass,
  );
  late final TextEditingController _host = TextEditingController(
    text: widget.proxy.host,
  );
  late final TextEditingController _sni = TextEditingController(
    text: widget.proxy.sni,
  );
  late final TextEditingController _bodySize = TextEditingController(
    text: '${jInt(widget.proxy.extra['client_max_body_size'])}',
  );

  bool _expanded = false;

  @override
  void dispose() {
    _location.dispose();
    _pass.dispose();
    _host.dispose();
    _sni.dispose();
    _bodySize.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = widget.proxy;
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
                    controller: _location,
                    decoration: const InputDecoration(
                      labelText: '匹配路径',
                      hintText: '/',
                    ),
                    onChanged: (v) {
                      p.location = v.trim();
                      widget.onChanged();
                    },
                  ),
                ),
                A11yIconButton(
                  tooltip: p.location.isEmpty
                      ? '删除这条代理规则'
                      : '删除代理规则 ${p.location}',
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
                  TextField(
                    controller: _pass,
                    decoration: const InputDecoration(
                      labelText: '代理地址',
                      hintText: 'http://127.0.0.1:8080',
                    ),
                    onChanged: (v) {
                      p.pass = v.trim();
                      widget.onChanged();
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _host,
                    decoration: const InputDecoration(
                      labelText: '代理 Host',
                      hintText: r'$host',
                    ),
                    onChanged: (v) {
                      p.host = v.trim();
                      widget.onChanged();
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: const Text('启用缓冲'),
                          value: p.buffering,
                          onChanged: (v) {
                            setState(() => p.buffering = v);
                            widget.onChanged();
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue:
                              const ['1.0', '1.1', '2'].contains(p.httpVersion)
                              ? p.httpVersion
                              : '1.1',
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'HTTP 版本',
                          ),
                          items: const [
                            DropdownMenuItem(value: '1.0', child: Text('1.0')),
                            DropdownMenuItem(value: '1.1', child: Text('1.1')),
                            DropdownMenuItem(value: '2', child: Text('2')),
                          ],
                          onChanged: (v) {
                            setState(() => p.httpVersion = v ?? '1.1');
                            widget.onChanged();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _expanded = !_expanded),
                      icon: ExpandChevron(expanded: _expanded),
                      label: Text(_expanded ? '收起高级选项' : '展开高级选项'),
                    ),
                  ),
                  AnimatedReveal(
                    visible: _expanded,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _sni,
                          decoration: const InputDecoration(
                            labelText: '代理 SNI',
                            hintText: 'example.com',
                          ),
                          onChanged: (v) {
                            p.sni = v.trim();
                            widget.onChanged();
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _bodySize,
                          keyboardType: TextInputType.number,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          decoration: const InputDecoration(
                            labelText: '请求体大小限制（字节）',
                            hintText: '0 表示使用全局配置',
                          ),
                          validator: (value) =>
                              _validateNonNegativeInt(value, '留空或 0 表示使用全局配置'),
                          onChanged: (v) {
                            final t = v.trim();
                            final n = t.isEmpty ? 0 : int.tryParse(t);
                            // 非法输入不写回模型，由 validator 提示用户修正。
                            if (n != null && n >= 0) {
                              p.extra['client_max_body_size'] = n;
                            }
                            widget.onChanged();
                          },
                        ),
                        const SizedBox(height: 16),
                        KeyValueListField(
                          label: '自定义请求头',
                          initialValues: jStringMap(p.extra['headers']),
                          keyHint: 'X-Custom-Header',
                          valueHint: 'value',
                          addButtonText: '添加请求头',
                          onChanged: (v) {
                            p.extra['headers'] = v;
                            widget.onChanged();
                          },
                        ),
                        const SizedBox(height: 8),
                        KeyValueListField(
                          label: '响应内容替换',
                          initialValues: jStringMap(p.extra['replaces']),
                          keyHint: '/old',
                          valueHint: '/new',
                          addButtonText: '添加替换',
                          onChanged: (v) {
                            p.extra['replaces'] = v;
                            widget.onChanged();
                          },
                        ),
                      ],
                    ),
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
