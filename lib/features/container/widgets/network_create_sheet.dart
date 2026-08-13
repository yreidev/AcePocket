import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/a11y.dart';
import '../models/container_network.dart';
import '../models/kv.dart';
import '../providers/container_providers.dart';
import 'action_runner.dart';
import 'kv_editor.dart';

/// 弹出「创建网络」面板。返回 true 表示创建成功。
Future<bool> showNetworkCreateSheet(BuildContext context) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => const _NetworkCreateSheet(),
  );
  return result ?? false;
}

class _NetworkCreateSheet extends ConsumerStatefulWidget {
  const _NetworkCreateSheet();

  @override
  ConsumerState<_NetworkCreateSheet> createState() =>
      _NetworkCreateSheetState();
}

class _NetworkCreateSheetState extends ConsumerState<_NetworkCreateSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  final _ipv4Subnet = TextEditingController();
  final _ipv4Gateway = TextEditingController();
  final _ipv4Range = TextEditingController();
  final _ipv6Subnet = TextEditingController();
  final _ipv6Gateway = TextEditingController();
  final _ipv6Range = TextEditingController();

  String _driver = 'bridge';
  bool _ipv4Enabled = false;
  bool _ipv6Enabled = false;
  List<KV> _labels = const [];
  List<KV> _options = const [];
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _ipv4Subnet.dispose();
    _ipv4Gateway.dispose();
    _ipv4Range.dispose();
    _ipv6Subnet.dispose();
    _ipv6Gateway.dispose();
    _ipv6Range.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    final navigator = Navigator.of(context);
    final ok = await runAction(
      context,
      pending: '正在创建网络…',
      success: '网络已创建',
      action: () => ref
          .read(containerRepoProvider)
          .createNetwork(
            name: _nameController.text.trim(),
            driver: _driver,
            ipv4: ContainerNetworkFamilyConfig(
              enabled: _ipv4Enabled,
              subnet: _ipv4Subnet.text.trim(),
              gateway: _ipv4Gateway.text.trim(),
              ipRange: _ipv4Range.text.trim(),
            ),
            ipv6: ContainerNetworkFamilyConfig(
              enabled: _ipv6Enabled,
              subnet: _ipv6Subnet.text.trim(),
              gateway: _ipv6Gateway.text.trim(),
              ipRange: _ipv6Range.text.trim(),
            ),
            labels: _labels,
            options: _options,
          ),
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok) navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('创建网络', style: theme.textTheme.titleMedium),
                  ),
                  A11yIconButton(
                    tooltip: '关闭创建网络面板',
                    icon: const Icon(Icons.close),
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  children: [
                    TextFormField(
                      controller: _nameController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: '网络名称',
                        helperText: '仅允许字母、数字、下划线与短横线',
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[a-zA-Z0-9_-]'),
                        ),
                      ],
                      validator: (value) {
                        final text = (value ?? '').trim();
                        if (text.isEmpty) return '请输入网络名称';
                        if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(text)) {
                          return '仅允许字母、数字、下划线与短横线';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _driver,
                      decoration: const InputDecoration(labelText: '驱动'),
                      items: [
                        for (final driver in containerNetworkDrivers)
                          DropdownMenuItem(value: driver, child: Text(driver)),
                      ],
                      onChanged: (value) =>
                          setState(() => _driver = value ?? 'bridge'),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('自定义 IPv4 子网'),
                      value: _ipv4Enabled,
                      onChanged: (value) =>
                          setState(() => _ipv4Enabled = value),
                    ),
                    if (_ipv4Enabled) ...[
                      TextFormField(
                        controller: _ipv4Subnet,
                        decoration: const InputDecoration(
                          labelText: '子网',
                          hintText: '如 172.20.0.0/16',
                        ),
                        validator: (value) =>
                            _ipv4Enabled && (value ?? '').trim().isEmpty
                            ? '请输入 IPv4 子网'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _ipv4Gateway,
                        decoration: const InputDecoration(
                          labelText: '网关',
                          hintText: '如 172.20.0.1',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _ipv4Range,
                        decoration: const InputDecoration(
                          labelText: 'IP 范围（可选）',
                          hintText: '如 172.20.10.0/24',
                        ),
                      ),
                    ],
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('自定义 IPv6 子网'),
                      value: _ipv6Enabled,
                      onChanged: (value) =>
                          setState(() => _ipv6Enabled = value),
                    ),
                    if (_ipv6Enabled) ...[
                      TextFormField(
                        controller: _ipv6Subnet,
                        decoration: const InputDecoration(
                          labelText: '子网',
                          hintText: '如 fd00::/64',
                        ),
                        validator: (value) =>
                            _ipv6Enabled && (value ?? '').trim().isEmpty
                            ? '请输入 IPv6 子网'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _ipv6Gateway,
                        decoration: const InputDecoration(labelText: '网关'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _ipv6Range,
                        decoration: const InputDecoration(
                          labelText: 'IP 范围（可选）',
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text('标签', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    KvEditor(
                      initialValue: const [],
                      onChanged: (value) => _labels = value,
                      addLabel: '添加标签',
                    ),
                    const SizedBox(height: 8),
                    Text('驱动选项', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    KvEditor(
                      initialValue: const [],
                      onChanged: (value) => _options = value,
                      addLabel: '添加选项',
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _submitting ? null : _submit,
                      icon: const Icon(Icons.check),
                      label: const Text('创建'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
