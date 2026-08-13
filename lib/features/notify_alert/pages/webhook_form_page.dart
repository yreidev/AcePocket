import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/unsaved_guard.dart';
import '../models/webhook.dart';
import '../providers/notify_alert_providers.dart';
import '../widgets/form_fields.dart';

/// WebHook 表单页 `/webhooks/new` 与 `/webhooks/:id/edit`。
class WebhookFormPage extends ConsumerStatefulWidget {
  const WebhookFormPage({super.key, this.webhookId});

  /// 为 null 时是新建。
  final int? webhookId;

  @override
  ConsumerState<WebhookFormPage> createState() => _WebhookFormPageState();
}

class _WebhookFormPageState extends ConsumerState<WebhookFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _userController = TextEditingController();
  final _scriptController = TextEditingController();

  bool _initialized = false;
  bool _saving = false;
  bool _raw = false;
  bool _status = true;
  String _key = '';

  /// 表单是否有未保存的修改（与加载时的原始值逐项比较）。
  bool _dirty = false;

  /// [_apply] 回填控件期间不计入修改。
  bool _applying = false;

  /// 原始值快照。
  String _pristine = '';

  bool get _isEdit => widget.webhookId != null;

  @override
  void initState() {
    super.initState();
    for (final controller in <TextEditingController>[
      _nameController,
      _userController,
      _scriptController,
    ]) {
      controller.addListener(_onFieldChanged);
    }
    if (!_isEdit) _apply(WebHook.empty());
  }

  /// 当前表单值的快照，用于判断是否有未保存的修改。
  String _snapshot() => <String>[
    _nameController.text.trim(),
    _userController.text.trim(),
    _scriptController.text,
    '$_raw',
    '$_status',
  ].join('\u0000');

  void _onFieldChanged() {
    if (_applying) return;
    final dirty = _snapshot() != _pristine;
    if (dirty != _dirty && mounted) setState(() => _dirty = dirty);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _userController.dispose();
    _scriptController.dispose();
    super.dispose();
  }

  void _apply(WebHook webhook) {
    _applying = true;
    _nameController.text = webhook.name;
    _userController.text = webhook.displayUser;
    _scriptController.text = webhook.script;
    _raw = webhook.raw;
    _status = webhook.status;
    _key = webhook.key;
    _initialized = true;
    _pristine = _snapshot();
    _dirty = false;
    _applying = false;
  }

  Future<void> _copyUrl() async {
    final baseUrl = ref.read(webhookBaseUrlProvider);
    await Clipboard.setData(ClipboardData(text: '$baseUrl$_key'));
    if (mounted) showSuccessSnack(context, '回调地址已复制到剪贴板');
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final webhook = WebHook(
      id: widget.webhookId ?? 0,
      name: _nameController.text.trim(),
      key: _key,
      script: _scriptController.text,
      raw: _raw,
      user: _userController.text.trim(),
      status: _status,
      callCount: 0,
    );

    setState(() => _saving = true);
    try {
      final repo = ref.read(notifyAlertRepoProvider);
      if (_isEdit) {
        await repo.updateWebhook(webhook);
      } else {
        await repo.createWebhook(webhook);
      }
      if (!mounted) return;
      _dirty = false;
      showSuccessSnack(context, _isEdit ? 'WebHook 已保存' : 'WebHook 已创建');
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
    final title = _isEdit ? '编辑 WebHook' : '新建 WebHook';

    if (_isEdit && !_initialized) {
      final async = ref.watch(webhookProvider(widget.webhookId!));
      if (!async.hasValue) {
        return Scaffold(
          appBar: AppBar(title: Text(title)),
          body: async.hasError
              ? ErrorView(
                  error: async.error!,
                  onRetry: () =>
                      ref.invalidate(webhookProvider(widget.webhookId!)),
                )
              : const LoadingView(message: '加载 WebHook…'),
        );
      }
      _apply(async.requireValue);
    }

    return UnsavedChangesGuard(
      hasUnsavedChanges: _dirty,
      message: 'WebHook 尚未保存，返回后填写的脚本与配置会丢失。确定放弃吗？',
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [_basicCard(), _scriptCard()],
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
    final theme = Theme.of(context);
    final baseUrl = ref.watch(webhookBaseUrlProvider);
    return SectionCard(
      title: '基本信息',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: '名称',
              hintText: '如：重启 Nginx',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            textInputAction: TextInputAction.next,
            validator: (value) =>
                (value == null || value.trim().isEmpty) ? '请填写名称' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _userController,
            decoration: const InputDecoration(
              labelText: '执行用户',
              hintText: 'root',
              helperText: '以该系统用户身份执行脚本，留空视为 root',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            autocorrect: false,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _raw,
            onChanged: (value) {
              setState(() => _raw = value);
              _onFieldChanged();
            },
            title: const Text('原始输出'),
            subtitle: const Text('以纯文本返回脚本输出，而非 JSON 包装'),
            contentPadding: EdgeInsets.zero,
          ),
          if (_isEdit)
            SwitchListTile(
              value: _status,
              onChanged: (value) {
                setState(() => _status = value);
                _onFieldChanged();
              },
              title: const Text('启用'),
              subtitle: const Text('停用后回调请求不会执行脚本'),
              contentPadding: EdgeInsets.zero,
            ),
          if (_isEdit && _key.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '回调地址',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    '$baseUrl$_key',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                A11yIconButton(
                  tooltip: '复制回调地址',
                  onPressed: _copyUrl,
                  icon: const Icon(Icons.copy_all_outlined),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _scriptCard() {
    final theme = Theme.of(context);
    return SectionCard(
      title: '脚本内容',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const InfoBanner(
            margin: EdgeInsets.only(bottom: 12),
            text:
                '脚本会保存为面板服务器上的可执行文件，请谨慎填写。'
                '建议以 #!/bin/bash 开头。',
          ),
          TextFormField(
            controller: _scriptController,
            minLines: 10,
            maxLines: 24,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            autocorrect: false,
            enableSuggestions: false,
            smartDashesType: SmartDashesType.disabled,
            smartQuotesType: SmartQuotesType.disabled,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
              height: 1.4,
            ),
            decoration: const InputDecoration(
              hintText: '#!/bin/bash\n\nsystemctl restart nginx',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            validator: (value) =>
                (value == null || value.trim().isEmpty) ? '请填写脚本内容' : null,
          ),
        ],
      ),
    );
  }
}
