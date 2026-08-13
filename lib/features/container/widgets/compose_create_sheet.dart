import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../models/kv.dart';
import '../providers/container_providers.dart';
import 'action_runner.dart';
import 'kv_editor.dart';

/// 新建编排时预填的示例内容。
const String _composeTemplate = '''services:
  app:
    image: nginx:alpine
    restart: unless-stopped
    ports:
      - "80:80"
''';

/// 弹出「新建编排」面板。返回创建成功的编排名称，取消时返回 null。
Future<String?> showComposeCreateSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => const _ComposeCreateSheet(),
  );
}

class _ComposeCreateSheet extends ConsumerStatefulWidget {
  const _ComposeCreateSheet();

  @override
  ConsumerState<_ComposeCreateSheet> createState() =>
      _ComposeCreateSheetState();
}

class _ComposeCreateSheetState extends ConsumerState<_ComposeCreateSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _composeController = TextEditingController(text: _composeTemplate);

  List<KV> _envs = const [];
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _composeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final name = _nameController.text.trim();
    setState(() => _submitting = true);
    final navigator = Navigator.of(context);
    final ok = await runAction(
      context,
      pending: '正在创建编排…',
      success: '编排「$name」已创建',
      action: () => ref.read(containerRepoProvider).createCompose(
            name: name,
            compose: _composeController.text,
            envs: _envs,
          ),
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok) navigator.pop(name);
  }

  /// 是否已经填过内容（模板原样不算）。
  bool get _hasInput =>
      _nameController.text.trim().isNotEmpty ||
      _composeController.text != _composeTemplate ||
      _envs.isNotEmpty;

  /// 关闭面板：已填内容时先确认，避免误触关闭丢掉整段编排。
  Future<void> _close() async {
    final navigator = Navigator.of(context);
    if (_hasInput) {
      final ok = await showConfirmDialog(
        context,
        title: '放弃新建编排',
        content: '已填写的编排内容将丢失，确定放弃吗？',
        confirmText: '放弃',
        cancelText: '继续编辑',
        danger: true,
      );
      if (!ok) return;
    }
    if (navigator.mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    // 已填内容时拦截系统返回手势 / 返回键，与关闭按钮走同一条确认流程，
    // 避免一次误触丢掉整段编排。
    return PopScope<String?>(
      canPop: !_hasInput && !_submitting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('新建编排', style: theme.textTheme.titleMedium),
                    ),
                    A11yIconButton(
                      tooltip: '关闭新建编排面板',
                      icon: const Icon(Icons.close),
                      onPressed: _submitting ? null : _close,
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
                          labelText: '编排名称',
                          helperText: '仅允许字母、数字、下划线与短横线',
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[a-zA-Z0-9_-]'),
                          ),
                        ],
                        validator: (value) {
                          final text = (value ?? '').trim();
                          if (text.isEmpty) return '请输入编排名称';
                          if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(text)) {
                            return '仅允许字母、数字、下划线与短横线';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      Text('docker-compose.yml',
                          style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _composeController,
                        maxLines: null,
                        minLines: 10,
                        keyboardType: TextInputType.multiline,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontFamilyFallback: ['Courier'],
                          fontSize: 13,
                          height: 1.5,
                        ),
                        decoration: const InputDecoration(
                          alignLabelWithHint: true,
                          hintText: 'services: …',
                        ),
                        validator: (value) =>
                            (value ?? '').trim().isEmpty ? '请输入编排内容' : null,
                      ),
                      const SizedBox(height: 16),
                      Text('环境变量（.env）', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      KvEditor(
                        initialValue: const [],
                        onChanged: (value) => _envs = value,
                        keyHint: '变量名',
                        valueHint: '变量值',
                        addLabel: '添加变量',
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
      ),
    );
  }
}
