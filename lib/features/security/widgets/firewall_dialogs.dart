import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/input_validation.dart';
import '../models/firewall_models.dart';

const _protocols = ['tcp', 'udp', 'tcp/udp'];
const _families = ['ipv4', 'ipv6'];
const _strategies = ['accept', 'drop', 'reject'];
const _directions = ['in', 'out'];

/// 新建防火墙端口规则（返回 null 表示取消）。
///
/// 返回的 [FirewallRule] 仅承载表单值，`type` / `inUse` 不参与创建请求。
Future<FirewallRule?> showFirewallRuleSheet(BuildContext context) {
  return _showFormSheet<FirewallRule>(
    context,
    title: '新建端口规则',
    builder: (context, formKey) => _FirewallRuleForm(formKey: formKey),
  );
}

/// 新建防火墙 IP 规则。
Future<FirewallIpRule?> showFirewallIpRuleSheet(BuildContext context) {
  return _showFormSheet<FirewallIpRule>(
    context,
    title: '新建 IP 规则',
    builder: (context, formKey) => _FirewallIpRuleForm(formKey: formKey),
  );
}

/// 新建端口转发规则。
Future<FirewallForward?> showFirewallForwardSheet(BuildContext context) {
  return _showFormSheet<FirewallForward>(
    context,
    title: '新建端口转发',
    builder: (context, formKey) => _FirewallForwardForm(formKey: formKey),
  );
}

Future<T?> _showFormSheet<T>(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext context, GlobalKey<FormState> formKey)
  builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) {
      final formKey = GlobalKey<FormState>();
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                builder(context, formKey),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// 表单内的分段选择器。
class _SegmentedField extends StatelessWidget {
  const _SegmentedField({
    required this.label,
    required this.options,
    required this.value,
    required this.labelBuilder,
    required this.onChanged,
  });

  final String label;
  final List<String> options;
  final String value;
  final String Function(String option) labelBuilder;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            segments: [
              for (final option in options)
                ButtonSegment<String>(
                  value: option,
                  label: Text(labelBuilder(option)),
                ),
            ],
            selected: {value},
            showSelectedIcon: false,
            onSelectionChanged: (selection) => onChanged(selection.first),
          ),
        ),
      ],
    );
  }
}

String? _portValidator(String? value) {
  final port = int.tryParse((value ?? '').trim());
  if (port == null) return '请输入端口号';
  if (port < 1 || port > 65535) return '端口需在 1-65535 之间';
  return null;
}

final _digitsOnly = [FilteringTextInputFormatter.digitsOnly];

class _FirewallRuleForm extends StatefulWidget {
  const _FirewallRuleForm({required this.formKey});

  final GlobalKey<FormState> formKey;

  @override
  State<_FirewallRuleForm> createState() => _FirewallRuleFormState();
}

class _FirewallRuleFormState extends State<_FirewallRuleForm> {
  final TextEditingController _portStart = TextEditingController(text: '80');
  final TextEditingController _portEnd = TextEditingController(text: '80');
  final TextEditingController _address = TextEditingController();

  String _protocol = 'tcp';
  String _family = 'ipv4';
  String _strategy = 'accept';
  String _direction = 'in';

  @override
  void dispose() {
    _portStart.dispose();
    _portEnd.dispose();
    _address.dispose();
    super.dispose();
  }

  void _submit() {
    if (!widget.formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      FirewallRule(
        type: '',
        family: _family,
        portStart: int.parse(_portStart.text.trim()),
        portEnd: int.parse(_portEnd.text.trim()),
        protocol: _protocol,
        address: _address.text.trim(),
        strategy: _strategy,
        direction: _direction,
        inUse: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: widget.formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SegmentedField(
            label: '传输协议',
            options: _protocols,
            value: _protocol,
            labelBuilder: (v) => v.toUpperCase(),
            onChanged: (v) => setState(() => _protocol = v),
          ),
          const SizedBox(height: 16),
          _SegmentedField(
            label: '网络协议',
            options: _families,
            value: _family,
            labelBuilder: FirewallLabels.family,
            onChanged: (v) => setState(() => _family = v),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _portStart,
                  keyboardType: TextInputType.number,
                  inputFormatters: _digitsOnly,
                  decoration: const InputDecoration(
                    labelText: '起始端口',
                    border: OutlineInputBorder(),
                  ),
                  validator: _portValidator,
                  onChanged: (value) {
                    final start = int.tryParse(value.trim());
                    final end = int.tryParse(_portEnd.text.trim());
                    if (start != null && (end == null || end < start)) {
                      _portEnd.text = value.trim();
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _portEnd,
                  keyboardType: TextInputType.number,
                  inputFormatters: _digitsOnly,
                  decoration: const InputDecoration(
                    labelText: '结束端口',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final error = _portValidator(value);
                    if (error != null) return error;
                    final start = int.tryParse(_portStart.text.trim());
                    final end = int.tryParse((value ?? '').trim());
                    if (start != null && end != null && end < start) {
                      return '不能小于起始端口';
                    }
                    return null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _address,
            decoration: const InputDecoration(
              labelText: '来源地址（可选）',
              hintText: '172.16.0.1 或 172.16.0.0/16',
              helperText: '留空表示不限制来源',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              final text = (value ?? '').trim();
              if (text.isEmpty) return null;
              return validateIpOrCidr(text, family: _family);
            },
          ),
          const SizedBox(height: 16),
          _SegmentedField(
            label: '策略',
            options: _strategies,
            value: _strategy,
            labelBuilder: FirewallLabels.strategy,
            onChanged: (v) => setState(() => _strategy = v),
          ),
          const SizedBox(height: 16),
          _SegmentedField(
            label: '方向',
            options: _directions,
            value: _direction,
            labelBuilder: FirewallLabels.direction,
            onChanged: (v) => setState(() => _direction = v),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _submit, child: const Text('创建')),
        ],
      ),
    );
  }
}

class _FirewallIpRuleForm extends StatefulWidget {
  const _FirewallIpRuleForm({required this.formKey});

  final GlobalKey<FormState> formKey;

  @override
  State<_FirewallIpRuleForm> createState() => _FirewallIpRuleFormState();
}

class _FirewallIpRuleFormState extends State<_FirewallIpRuleForm> {
  final TextEditingController _address = TextEditingController();

  String _protocol = 'tcp';
  String _family = 'ipv4';
  String _strategy = 'drop';
  String _direction = 'in';

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  void _submit() {
    if (!widget.formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      FirewallIpRule(
        family: _family,
        protocol: _protocol,
        address: _address.text.trim(),
        strategy: _strategy,
        direction: _direction,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: widget.formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SegmentedField(
            label: '传输协议',
            options: _protocols,
            value: _protocol,
            labelBuilder: (v) => v.toUpperCase(),
            onChanged: (v) => setState(() => _protocol = v),
          ),
          const SizedBox(height: 16),
          _SegmentedField(
            label: '网络协议',
            options: _families,
            value: _family,
            labelBuilder: FirewallLabels.family,
            onChanged: (v) => setState(() => _family = v),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _address,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'IP 地址 / 网段',
              hintText: '172.16.0.1 或 172.16.0.0/16',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              final text = (value ?? '').trim();
              if (text.isEmpty) return '请输入 IP 地址或网段';
              return validateIpOrCidr(text, family: _family);
            },
          ),
          const SizedBox(height: 16),
          _SegmentedField(
            label: '策略',
            options: _strategies,
            value: _strategy,
            labelBuilder: FirewallLabels.strategy,
            onChanged: (v) => setState(() => _strategy = v),
          ),
          const SizedBox(height: 16),
          _SegmentedField(
            label: '方向',
            options: _directions,
            value: _direction,
            labelBuilder: FirewallLabels.direction,
            onChanged: (v) => setState(() => _direction = v),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _submit, child: const Text('创建')),
        ],
      ),
    );
  }
}

class _FirewallForwardForm extends StatefulWidget {
  const _FirewallForwardForm({required this.formKey});

  final GlobalKey<FormState> formKey;

  @override
  State<_FirewallForwardForm> createState() => _FirewallForwardFormState();
}

class _FirewallForwardFormState extends State<_FirewallForwardForm> {
  final TextEditingController _port = TextEditingController(text: '8080');
  final TextEditingController _targetIp = TextEditingController(
    text: '127.0.0.1',
  );
  final TextEditingController _targetPort = TextEditingController(text: '80');

  String _protocol = 'tcp';

  @override
  void dispose() {
    _port.dispose();
    _targetIp.dispose();
    _targetPort.dispose();
    super.dispose();
  }

  void _submit() {
    if (!widget.formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      FirewallForward(
        protocol: _protocol,
        port: int.parse(_port.text.trim()),
        targetIp: _targetIp.text.trim(),
        targetPort: int.parse(_targetPort.text.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: widget.formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SegmentedField(
            label: '传输协议',
            options: _protocols,
            value: _protocol,
            labelBuilder: (v) => v.toUpperCase(),
            onChanged: (v) => setState(() => _protocol = v),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _port,
            keyboardType: TextInputType.number,
            inputFormatters: _digitsOnly,
            decoration: const InputDecoration(
              labelText: '源端口',
              border: OutlineInputBorder(),
            ),
            validator: _portValidator,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _targetIp,
            decoration: const InputDecoration(
              labelText: '目标 IP',
              hintText: '127.0.0.1',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              final text = (value ?? '').trim();
              if (text.isEmpty) return '请输入目标 IP';
              return validateIpAddress(text);
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _targetPort,
            keyboardType: TextInputType.number,
            inputFormatters: _digitsOnly,
            decoration: const InputDecoration(
              labelText: '目标端口',
              border: OutlineInputBorder(),
            ),
            validator: _portValidator,
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _submit, child: const Text('创建')),
        ],
      ),
    );
  }
}

/// 端口占用进程查看对话框。
Future<void> showPortUsageDialog(
  BuildContext context, {
  required int port,
  required String protocol,
  required Future<List<PortProcess>> future,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        title: Text('端口 $port（${protocol.toUpperCase()}）占用'),
        content: SizedBox(
          width: double.maxFinite,
          child: FutureBuilder<List<PortProcess>>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const SizedBox(
                  height: 80,
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }
              if (snapshot.hasError) {
                return Text(
                  '${snapshot.error}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                );
              }
              final processes = snapshot.data ?? const <PortProcess>[];
              if (processes.isEmpty) {
                return Text(
                  '该端口当前没有监听进程',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                );
              }
              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: processes.length,
                  separatorBuilder: (_, _) => const Divider(height: 16),
                  itemBuilder: (context, index) {
                    final process = processes[index];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${process.name}（PID ${process.pid}）',
                          style: theme.textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          process.command,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    );
                  },
                ),
              );
            },
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      );
    },
  );
}
