import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/input_validation.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/unsaved_guard.dart';
import '../models/notify_channel.dart';
import '../providers/notify_alert_providers.dart';
import '../widgets/form_fields.dart';

/// 通知渠道表单页 `/notify/channels/new` 与 `/notify/channels/:id/edit`。
///
/// 面板目前仅实现 SMTP 邮件渠道（`request.NotifyChannelCreate` 校验 `in:smtp`），
/// 因此表单只展示 SMTP 配置项。
class NotifyChannelFormPage extends ConsumerStatefulWidget {
  const NotifyChannelFormPage({super.key, this.channelId});

  /// 为 null 时是新建。
  final int? channelId;

  @override
  ConsumerState<NotifyChannelFormPage> createState() =>
      _NotifyChannelFormPageState();
}

class _NotifyChannelFormPageState extends ConsumerState<NotifyChannelFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _fromController = TextEditingController();
  final _fromNameController = TextEditingController();

  bool _initialized = false;
  bool _saving = false;
  bool _obscurePassword = true;

  /// 表单是否有未保存的修改（与加载时的原始值逐项比较）。
  bool _dirty = false;

  /// [_apply] 回填控件期间不计入修改。
  bool _applying = false;

  /// 原始值快照。
  String _pristine = '';

  String _encryption = kSmtpEncryptionSsl;
  List<String> _recipients = <String>[];
  bool _skipVerify = false;
  bool _enabled = true;

  bool get _isEdit => widget.channelId != null;

  @override
  void initState() {
    super.initState();
    for (final controller in <TextEditingController>[
      _nameController,
      _hostController,
      _portController,
      _usernameController,
      _passwordController,
      _fromController,
      _fromNameController,
    ]) {
      controller.addListener(_onFieldChanged);
    }
    if (!_isEdit) {
      _apply(
        const NotifyChannel(
          id: 0,
          name: '',
          type: kNotifyTypeSmtp,
          config: <String, dynamic>{},
          enabled: true,
        ),
      );
    }
  }

  /// 当前表单值的快照，用于判断是否有未保存的修改。
  String _snapshot() => <String>[
    _nameController.text.trim(),
    _hostController.text.trim(),
    _portController.text.trim(),
    _usernameController.text.trim(),
    _passwordController.text,
    _fromController.text.trim(),
    _fromNameController.text.trim(),
    _encryption,
    '$_skipVerify',
    '$_enabled',
    _recipients.map((e) => e.trim()).where((e) => e.isNotEmpty).join(','),
  ].join('\u0000');

  void _onFieldChanged() {
    if (_applying) return;
    final dirty = _snapshot() != _pristine;
    if (dirty != _dirty && mounted) setState(() => _dirty = dirty);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _fromController.dispose();
    _fromNameController.dispose();
    super.dispose();
  }

  void _apply(NotifyChannel channel) {
    _applying = true;
    final smtp = SmtpConfig.fromJson(channel.config);
    _nameController.text = channel.name;
    _hostController.text = smtp.host;
    _portController.text = '${smtp.port}';
    _usernameController.text = smtp.username;
    _passwordController.text = smtp.password;
    _fromController.text = smtp.from;
    _fromNameController.text = smtp.fromName;
    _encryption = smtp.encryption;
    _recipients = List<String>.from(smtp.to);
    _skipVerify = smtp.skipVerify;
    _enabled = channel.enabled;
    _initialized = true;
    _pristine = _snapshot();
    _dirty = false;
    _applying = false;
  }

  /// 切换加密方式时同步常用端口（与面板前端一致）。
  void _onEncryptionChanged(String encryption) {
    setState(() {
      _encryption = encryption;
      _portController.text = '${smtpDefaultPort(encryption)}';
    });
    _onFieldChanged();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final recipients = _recipients
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (recipients.isEmpty) {
      showErrorSnack(context, '请至少填写一个收件人');
      return;
    }
    for (final recipient in recipients) {
      final error = validateEmail(recipient);
      if (error != null) {
        showErrorSnack(context, '收件人 $recipient：$error');
        return;
      }
    }

    final config = SmtpConfig(
      host: _hostController.text.trim(),
      port: int.tryParse(_portController.text.trim()) ?? 465,
      encryption: _encryption,
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      from: _fromController.text.trim(),
      fromName: _fromNameController.text.trim(),
      to: recipients,
      skipVerify: _skipVerify,
    );
    final channel = NotifyChannel(
      id: widget.channelId ?? 0,
      name: _nameController.text.trim(),
      type: kNotifyTypeSmtp,
      config: config.toJson(),
      enabled: _enabled,
    );

    setState(() => _saving = true);
    try {
      final repo = ref.read(notifyAlertRepoProvider);
      if (_isEdit) {
        await repo.updateNotifyChannel(channel);
      } else {
        await repo.createNotifyChannel(channel);
      }
      if (!mounted) return;
      _dirty = false;
      showSuccessSnack(context, _isEdit ? '渠道已保存' : '渠道已创建');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _isEdit ? '编辑通知渠道' : '新建通知渠道';

    if (_isEdit && !_initialized) {
      final async = ref.watch(notifyChannelProvider(widget.channelId!));
      if (!async.hasValue) {
        return Scaffold(
          appBar: AppBar(title: Text(title)),
          body: async.hasError
              ? ErrorView(
                  error: async.error!,
                  onRetry: () =>
                      ref.invalidate(notifyChannelProvider(widget.channelId!)),
                )
              : const LoadingView(message: '加载渠道配置…'),
        );
      }
      _apply(async.requireValue);
    }

    return UnsavedChangesGuard(
      hasUnsavedChanges: _dirty,
      message: '渠道配置尚未保存，返回后填写的内容会丢失。确定放弃吗？',
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [_basicCard(), _serverCard(), _senderCard()],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? '保存中…' : '保存'),
            ),
          ),
        ),
      ),
    );
  }

  Widget _basicCard() {
    return SectionCard(
      title: '基本信息',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: '渠道名称',
              hintText: '如：运维邮箱',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            textInputAction: TextInputAction.next,
            validator: (value) =>
                (value == null || value.trim().isEmpty) ? '请填写渠道名称' : null,
          ),
          const SizedBox(height: 16),
          const SelectField(
            label: '渠道类型',
            value: 'SMTP 邮件',
            onTap: null,
            helperText: '面板当前仅支持 SMTP 邮件渠道',
            icon: Icons.mail_outline,
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _enabled,
            onChanged: (value) {
              setState(() => _enabled = value);
              _onFieldChanged();
            },
            title: const Text('启用渠道'),
            subtitle: const Text('停用后不会向该渠道发送任何通知'),
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Widget _serverCard() {
    return SectionCard(
      title: 'SMTP 服务器',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _hostController,
            decoration: const InputDecoration(
              labelText: '服务器地址',
              hintText: 'smtp.example.com',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            autocorrect: false,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: (value) {
              final v = (value ?? '').trim();
              if (v.isEmpty) return '请填写 SMTP 服务器地址';
              // 只填主机名或 IP，validateDomain 的文案会提示去掉协议前缀/端口。
              return validateDomain(v, allowWildcard: false);
            },
          ),
          const SizedBox(height: 16),
          Text(
            '加密方式',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment<String>(
                  value: kSmtpEncryptionSsl,
                  label: Text('SSL/TLS', maxLines: 1),
                ),
                ButtonSegment<String>(
                  value: kSmtpEncryptionStartTls,
                  label: Text('STARTTLS', maxLines: 1),
                ),
                ButtonSegment<String>(
                  value: kSmtpEncryptionNone,
                  label: Text('不加密', maxLines: 1),
                ),
              ],
              selected: <String>{_encryption},
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onSelectionChanged: (selection) =>
                  _onEncryptionChanged(selection.first),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _portController,
            decoration: const InputDecoration(
              labelText: '端口',
              helperText: 'SSL/TLS 常用 465，STARTTLS 常用 587，不加密常用 25',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textInputAction: TextInputAction.next,
            validator: (value) {
              final parsed = int.tryParse((value ?? '').trim());
              if (parsed == null) return '请填写端口';
              if (parsed < 1 || parsed > 65535) return '端口取值范围 1~65535';
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _usernameController,
            decoration: const InputDecoration(
              labelText: '用户名',
              hintText: '登录账号，留空表示匿名投递',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            autocorrect: false,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: '密码',
              hintText: '登录密码或授权码',
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: IconButton(
                tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _skipVerify,
            onChanged: (value) {
              setState(() => _skipVerify = value);
              _onFieldChanged();
            },
            title: const Text('跳过证书校验'),
            subtitle: const Text('仅在服务器使用自签名证书时开启，开启后无法防止中间人攻击'),
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Widget _senderCard() {
    return SectionCard(
      title: '收发件设置',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _fromController,
            decoration: const InputDecoration(
              labelText: '发件地址',
              hintText: '留空时使用用户名',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            autocorrect: false,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: (value) {
              final v = (value ?? '').trim();
              if (v.isEmpty) return null;
              return validateEmail(v);
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _fromNameController,
            decoration: const InputDecoration(
              labelText: '发件人名称',
              hintText: 'AcePanel',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          StringListField(
            label: '收件人（至少一个）',
            hint: 'ops@example.com',
            keyboardType: TextInputType.emailAddress,
            initialValues: _recipients,
            minItems: 1,
            validator: validateEmail,
            onChanged: (values) {
              _recipients = values;
              _onFieldChanged();
            },
          ),
        ],
      ),
    );
  }
}
