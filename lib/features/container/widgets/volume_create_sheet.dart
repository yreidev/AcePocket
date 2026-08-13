import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/a11y.dart';
import '../models/kv.dart';
import '../providers/container_providers.dart';
import 'action_runner.dart';
import 'kv_editor.dart';

/// 弹出「创建存储卷」面板。返回 true 表示创建成功。
Future<bool> showVolumeCreateSheet(BuildContext context) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => const _VolumeCreateSheet(),
  );
  return result ?? false;
}

class _VolumeCreateSheet extends ConsumerStatefulWidget {
  const _VolumeCreateSheet();

  @override
  ConsumerState<_VolumeCreateSheet> createState() => _VolumeCreateSheetState();
}

class _VolumeCreateSheetState extends ConsumerState<_VolumeCreateSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  List<KV> _labels = const [];
  List<KV> _options = const [];
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    final navigator = Navigator.of(context);
    final ok = await runAction(
      context,
      pending: '正在创建存储卷…',
      success: '存储卷已创建',
      action: () => ref
          .read(containerRepoProvider)
          .createVolume(
            name: _nameController.text.trim(),
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
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('创建存储卷', style: theme.textTheme.titleMedium),
                  ),
                  A11yIconButton(
                    tooltip: '关闭创建存储卷面板',
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
                        labelText: '卷名称',
                        helperText: '仅允许字母、数字、下划线与短横线',
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[a-zA-Z0-9_-]'),
                        ),
                      ],
                      validator: (value) {
                        final text = (value ?? '').trim();
                        if (text.isEmpty) return '请输入卷名称';
                        if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(text)) {
                          return '仅允许字母、数字、下划线与短横线';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    const TextField(
                      enabled: false,
                      decoration: InputDecoration(
                        labelText: '驱动',
                        hintText: 'local',
                        helperText: '面板目前仅支持 local 驱动',
                      ),
                    ),
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
