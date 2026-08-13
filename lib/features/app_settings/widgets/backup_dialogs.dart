import 'package:flutter/material.dart';

import '../../../core/utils/format.dart';
import '../../../core/widgets/a11y.dart';
import '../models/config_backup.dart';
import '../repo/config_backup_repo.dart';

/// 导入时对已有服务器的处理方式。
enum BackupImportMode {
  /// 按 id 合并：同 id 覆盖，新 id 追加，本机独有的服务器保留。
  merge,

  /// 用备份里的服务器整体替换本机列表。
  replace,
}

/// 口令输入对话框，取消返回 null。
///
/// [isNew] 为 true 时用于导出：要求两次输入一致且不短于
/// [ConfigBackupRepo.minPassphraseLength]；为 false 时用于导入，只要非空。
Future<String?> showBackupPassphraseDialog(
  BuildContext context, {
  required bool isNew,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _PassphraseDialog(isNew: isNew),
  );
}

class _PassphraseDialog extends StatefulWidget {
  const _PassphraseDialog({required this.isNew});

  final bool isNew;

  @override
  State<_PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends State<_PassphraseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _passphrase = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _passphrase.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) return;
    Navigator.of(context).pop(_passphrase.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.isNew ? '设置备份口令' : '输入备份口令'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.isNew
                  ? '备份含 API 令牌与面板账号密码，会用该口令加密。'
                        '口令不会保存在任何地方，忘记后备份无法恢复。'
                  : '请输入导出这份备份时设置的口令。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passphrase,
              autofocus: true,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: '口令',
                suffixIcon: A11yIconButton(
                  tooltip: _obscure ? '显示口令' : '隐藏口令',
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (value) {
                final v = value ?? '';
                if (v.isEmpty) return '请输入口令';
                if (widget.isNew &&
                    v.length < ConfigBackupRepo.minPassphraseLength) {
                  return '口令至少 ${ConfigBackupRepo.minPassphraseLength} 位';
                }
                return null;
              },
              onFieldSubmitted: (_) => widget.isNew ? null : _submit(),
            ),
            if (widget.isNew) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirm,
                obscureText: _obscure,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(labelText: '再次输入口令'),
                validator: (value) =>
                    value == _passphrase.text ? null : '两次输入的口令不一致',
                onFieldSubmitted: (_) => _submit(),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.isNew ? '导出' : '导入'),
        ),
      ],
    );
  }
}

/// 导入前的预览与确认，取消返回 null。
Future<BackupImportMode?> showBackupImportDialog(
  BuildContext context, {
  required ConfigBackup backup,
  required int localServerCount,
}) {
  return showDialog<BackupImportMode>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      final names = backup.servers.map((s) => s.name).toList();
      return AlertDialog(
        title: const Text('导入配置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '导出时间：${formatDateTime(backup.createdAt)}'
              '${backup.appVersion.isEmpty ? '' : '\n导出版本：v${backup.appVersion}'}'
              '\n包含服务器：${backup.servers.length} 台'
              '${names.isEmpty ? '' : '（${names.join('、')}）'}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Text(
              localServerCount == 0
                  ? '本机当前没有服务器，两种方式效果相同。'
                  : '本机当前有 $localServerCount 台服务器。'
                        '「合并」会用同名 id 的备份覆盖它们并保留其余；'
                        '「替换」会清空本机列表只留备份内容。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '应用偏好（外观、启动页、刷新间隔、终端）会一并覆盖。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(BackupImportMode.replace),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            child: const Text('替换'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(BackupImportMode.merge),
            child: const Text('合并'),
          ),
        ],
      );
    },
  );
}
