import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/input_validation.dart';
import '../models/ssh_host.dart';

/// SSH 主机连接信息表单。
///
/// 字段与面板 `request.SSHCreate` / `request.SSHUpdate` 一一对应：
/// name（可空）、host、port（1-65535）、auth_method（password / publickey）、
/// user、password（密码认证必填）、key（密钥认证必填）、passphrase、remark。
class SshHostForm extends StatefulWidget {
  const SshHostForm({
    super.key,
    required this.initial,
    required this.submitting,
    required this.submitLabel,
    required this.onSubmit,
    this.onDirtyChanged,
  });

  /// 表单初值（新建传 [SshHostDraft.initial]，编辑传主机详情）。
  final SshHostDraft initial;

  /// 是否正在提交（提交中禁用按钮）。
  final bool submitting;

  final String submitLabel;

  final ValueChanged<SshHostDraft> onSubmit;

  /// 表单内容相对 [initial] 是否发生变化；供页面拦截「未保存就返回」。
  final ValueChanged<bool>? onDirtyChanged;

  @override
  State<SshHostForm> createState() => _SshHostFormState();
}

class _SshHostFormState extends State<SshHostForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _name =
      TextEditingController(text: widget.initial.name);
  late final TextEditingController _host =
      TextEditingController(text: widget.initial.host);
  late final TextEditingController _port =
      TextEditingController(text: widget.initial.port.toString());
  late final TextEditingController _user =
      TextEditingController(text: widget.initial.user);
  late final TextEditingController _password =
      TextEditingController(text: widget.initial.password);
  late final TextEditingController _key =
      TextEditingController(text: widget.initial.key);
  late final TextEditingController _passphrase =
      TextEditingController(text: widget.initial.passphrase);
  late final TextEditingController _remark =
      TextEditingController(text: widget.initial.remark);

  late SshAuthMethod _authMethod = widget.initial.authMethod;
  bool _obscurePassword = true;
  bool _obscurePassphrase = true;
  bool _dirty = false;

  /// 全部文本控制器，便于统一挂载 / 卸载「是否修改过」的监听。
  late final List<TextEditingController> _controllers = [
    _name,
    _host,
    _port,
    _user,
    _password,
    _key,
    _passphrase,
    _remark,
  ];

  @override
  void initState() {
    super.initState();
    for (final controller in _controllers) {
      controller.addListener(_notifyDirty);
    }
  }

  /// 与初值逐项比较，得出是否存在未保存的修改。
  ///
  /// 文本字段按提交时的口径（trim / 原样）比较，避免只敲了一个空格就把
  /// 「放弃修改」的确认框弹出来。
  bool _computeDirty() {
    final initial = widget.initial;
    return _name.text.trim() != initial.name.trim() ||
        _host.text.trim() != initial.host.trim() ||
        (int.tryParse(_port.text.trim()) ?? -1) != initial.port ||
        _authMethod != initial.authMethod ||
        _user.text.trim() != initial.user.trim() ||
        _password.text != initial.password ||
        _key.text.trim() != initial.key.trim() ||
        _passphrase.text != initial.passphrase ||
        _remark.text.trim() != initial.remark.trim();
  }

  void _notifyDirty() {
    final dirty = _computeDirty();
    if (dirty == _dirty) return;
    _dirty = dirty;
    widget.onDirtyChanged?.call(dirty);
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.removeListener(_notifyDirty);
    }
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _user.dispose();
    _password.dispose();
    _key.dispose();
    _passphrase.dispose();
    _remark.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    widget.onSubmit(
      SshHostDraft(
        name: _name.text.trim(),
        host: _host.text.trim(),
        port: int.parse(_port.text.trim()),
        authMethod: _authMethod,
        user: _user.text.trim(),
        password: _password.text,
        key: _key.text.trim(),
        passphrase: _passphrase.text,
        remark: _remark.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isKey = _authMethod == SshAuthMethod.publicKey;

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          TextFormField(
            controller: _name,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '名称',
              hintText: '如 生产 Web 01',
              helperText: '留空时列表展示主机地址',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: _host,
                  textInputAction: TextInputAction.next,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: '地址',
                    hintText: '127.0.0.1',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.isEmpty) return '请输入主机地址';
                    // 常见误填：把「地址:端口」整串填进地址框。
                    // IPv6 字面量含多个冒号，只拦截「一个冒号 + 纯数字」的情况。
                    final parts = text.split(':');
                    if (parts.length == 2 && int.tryParse(parts.last) != null) {
                      return '端口请填到右侧输入框';
                    }
                    // 其余情况交给通用校验：裸主机名或 IP（IPv4 / IPv6 均可），
                    // SSH 地址不是网站，不允许泛域名。
                    return validateDomain(text, allowWildcard: false);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: _port,
                  textInputAction: TextInputAction.next,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: '端口',
                    hintText: '22',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.isEmpty) return '请输入端口，如 22';
                    final port = int.tryParse(text);
                    if (port == null) return '端口应为数字，如 22';
                    if (port < 1 || port > 65535) {
                      return '端口需在 1-65535 之间';
                    }
                    return null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<SshAuthMethod>(
            initialValue: _authMethod,
            decoration: const InputDecoration(
              labelText: '认证方式',
              border: OutlineInputBorder(),
            ),
            items: SshAuthMethod.values
                .map((method) => DropdownMenuItem<SshAuthMethod>(
                      value: method,
                      child: Text(method.label),
                    ))
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() => _authMethod = value);
              _notifyDirty();
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _user,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: '用户名',
              hintText: 'root',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              final text = (value ?? '').trim();
              if (text.isEmpty) return '请输入用户名';
              // SSH 登录用户名不含空白字符，多为整串粘贴时带入。
              if (text.contains(RegExp(r'\s'))) return '用户名不能包含空格';
              return null;
            },
          ),
          const SizedBox(height: 16),
          if (!isKey)
            TextFormField(
              controller: _password,
              obscureText: _obscurePassword,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: '密码',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                  icon: Icon(_obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (value) => (value ?? '').isEmpty ? '密码认证必须填写密码' : null,
            )
          else ...[
            TextFormField(
              controller: _key,
              maxLines: 6,
              minLines: 4,
              autocorrect: false,
              enableSuggestions: false,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(
                labelText: '私钥',
                hintText: '-----BEGIN OPENSSH PRIVATE KEY-----',
                helperText: '粘贴完整的 PEM / OpenSSH 私钥内容',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? '密钥认证必须填写私钥' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passphrase,
              obscureText: _obscurePassphrase,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: '私钥密码',
                helperText: '私钥未加密时留空',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _obscurePassphrase ? '显示密码' : '隐藏密码',
                  icon: Icon(_obscurePassphrase
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  onPressed: () =>
                      setState(() => _obscurePassphrase = !_obscurePassphrase),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          TextFormField(
            controller: _remark,
            maxLines: 3,
            minLines: 2,
            decoration: const InputDecoration(
              labelText: '备注',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '保存时面板会先尝试建立 SSH 连接，连接失败则不会保存。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: widget.submitting ? null : _submit,
            child: widget.submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(widget.submitLabel),
          ),
        ],
      ),
    );
  }
}
