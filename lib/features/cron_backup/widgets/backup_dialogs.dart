import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/a11y.dart';
import '../models/backup_file.dart';
import '../providers/options_providers.dart';
import '../providers/storage_providers.dart';
import '../repo/backup_repo.dart';
import 'feedback.dart';
import 'format.dart';
import 'multi_select_field.dart';

/// 创建备份对话框的返回结果。
class CreateBackupResult {
  const CreateBackupResult({required this.target, required this.storage});

  final String target;
  final int storage;
}

/// 弹出「创建备份」对话框；取消时返回 null。
Future<CreateBackupResult?> showCreateBackupDialog(
  BuildContext context, {
  required String type,
}) {
  return showDialog<CreateBackupResult>(
    context: context,
    builder: (context) => _CreateBackupDialog(type: type),
  );
}

class _CreateBackupDialog extends ConsumerStatefulWidget {
  const _CreateBackupDialog({required this.type});

  final String type;

  @override
  ConsumerState<_CreateBackupDialog> createState() =>
      _CreateBackupDialogState();
}

class _CreateBackupDialogState extends ConsumerState<_CreateBackupDialog> {
  final _formKey = GlobalKey<FormState>();
  String? _target;
  int _storage = 0;

  bool get _fixedTarget =>
      widget.type == BackupTypes.redis || widget.type == BackupTypes.valkey;

  @override
  void initState() {
    super.initState();
    if (_fixedTarget) _target = widget.type;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('创建${BackupTypes.label(widget.type)}备份'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_fixedTarget)
                Text(
                  '${BackupTypes.label(widget.type)} 为整实例备份，无需选择具体库。',
                  style: theme.textTheme.bodyMedium,
                )
              else
                _TargetField(type: widget.type, onChanged: (v) => _target = v),
              const SizedBox(height: 16),
              _StorageField(
                value: _storage,
                onChanged: (v) => setState(() => _storage = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final form = _formKey.currentState;
            if (form != null && !form.validate()) return;
            final target = _target;
            if (target == null || target.isEmpty) {
              showErrorSnack(context, '请选择备份目标');
              return;
            }
            Navigator.of(context).pop(
              CreateBackupResult(target: target, storage: _storage),
            );
          },
          child: const Text('开始备份'),
        ),
      ],
    );
  }
}

/// 弹出「恢复备份」对话框，返回选择的目标；取消时返回 null。
Future<String?> showRestoreTargetDialog(
  BuildContext context, {
  required String type,
  required BackupFile file,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _RestoreDialog(type: type, file: file),
  );
}

class _RestoreDialog extends ConsumerStatefulWidget {
  const _RestoreDialog({required this.type, required this.file});

  final String type;
  final BackupFile file;

  @override
  ConsumerState<_RestoreDialog> createState() => _RestoreDialogState();
}

class _RestoreDialogState extends ConsumerState<_RestoreDialog> {
  final _formKey = GlobalKey<FormState>();
  String? _target;

  bool get _fixedTarget =>
      widget.type == BackupTypes.redis || widget.type == BackupTypes.valkey;

  @override
  void initState() {
    super.initState();
    if (_fixedTarget) _target = widget.type;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('恢复备份'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.file.name,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              if (_fixedTarget)
                Text(
                  '将恢复到 ${BackupTypes.label(widget.type)} 实例。',
                  style: theme.textTheme.bodyMedium,
                )
              else
                _TargetField(type: widget.type, onChanged: (v) => _target = v),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '恢复会覆盖目标上的现有数据，请谨慎操作。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: () {
            final form = _formKey.currentState;
            if (form != null && !form.validate()) return;
            final target = _target;
            if (target == null || target.isEmpty) {
              showErrorSnack(context, '请选择恢复目标');
              return;
            }
            Navigator.of(context).pop(target);
          },
          child: const Text('确认恢复'),
        ),
      ],
    );
  }
}

/// 备份目标选择（网站 / 数据库）。
class _TargetField extends ConsumerStatefulWidget {
  const _TargetField({required this.type, required this.onChanged});

  final String type;
  final ValueChanged<String?> onChanged;

  @override
  ConsumerState<_TargetField> createState() => _TargetFieldState();
}

class _TargetFieldState extends ConsumerState<_TargetField> {
  String? _value;

  @override
  Widget build(BuildContext context) {
    if (widget.type == BackupTypes.website) {
      return AsyncDropdownField(
        label: '网站',
        value: _value,
        options: ref.watch(websiteOptionsProvider),
        onReload: () => ref.invalidate(websiteOptionsProvider),
        onChanged: (v) {
          setState(() => _value = v);
          widget.onChanged(v);
        },
      );
    }
    if (BackupTypes.databaseTypes.contains(widget.type)) {
      final provider = databaseOptionsProvider(widget.type);
      return AsyncDropdownField(
        label: '数据库',
        value: _value,
        options: ref.watch(provider),
        onReload: () => ref.invalidate(provider),
        onChanged: (v) {
          setState(() => _value = v);
          widget.onChanged(v);
        },
      );
    }
    // 其他类型（如 panel）由调用方限制，不应走到这里；兜底为手动输入。
    return TextFormField(
      decoration: const InputDecoration(labelText: '目标名称'),
      onChanged: (v) {
        _value = v;
        widget.onChanged(v);
      },
      validator: (v) => (v == null || v.trim().isEmpty) ? '请填写目标名称' : null,
    );
  }
}

/// 备份存储选择。
class _StorageField extends ConsumerWidget {
  const _StorageField({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storages = ref.watch(storageOptionsProvider);
    return storages.when(
      loading: () => const InputDecorator(
        decoration: InputDecoration(labelText: '备份存储'),
        child: Text('加载中…'),
      ),
      error: (error, _) => InputDecorator(
        decoration: InputDecoration(
          labelText: '备份存储',
          errorText: describeError(error),
          suffixIcon: A11yIconButton(
            tooltip: '重新加载备份存储列表',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(storageOptionsProvider),
          ),
        ),
        child: const Text('加载失败，默认使用本地存储'),
      ),
      data: (list) {
        final ids = list.map((e) => e.id).toList();
        final current =
            ids.contains(value) ? value : (ids.isEmpty ? null : ids.first);
        // 选中的存储已被删除时下拉框会回退到第一项，这里把外部状态一并纠正，
        // 否则提交出去的仍是那个已失效的存储 ID。
        if (current != null && current != value) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) onChanged(current);
          });
        }
        return DropdownButtonFormField<int>(
          initialValue: current,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '备份存储'),
          items: [
            for (final option in list)
              DropdownMenuItem(
                value: option.id,
                child: Text(
                  option.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) => onChanged(v ?? 0),
        );
      },
    );
  }
}

/// 展示备份文件详情与下载信息。
///
/// [onDownload] 非空时提供「下载到本机」动作（点击后先关闭本对话框）。
Future<void> showBackupInfoDialog(
  BuildContext context, {
  required BackupFile file,
  required String type,
  required String baseUrl,
  VoidCallback? onDownload,
}) {
  final downloadPath = BackupRepo.downloadPath(type: type, file: file.name);
  return showDialog<void>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        title: const Text('备份文件'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoRow(label: '文件名', value: file.name),
              _InfoRow(label: '大小', value: file.size.isEmpty ? '-' : file.size),
              _InfoRow(label: '时间', value: formatDateTime(file.time)),
              _InfoRow(label: '服务器路径', value: file.path, copyable: true),
              _InfoRow(
                label: '下载接口',
                value: '$baseUrl$downloadPath',
                copyable: true,
              ),
              const SizedBox(height: 12),
              Text(
                '下载接口需要 API 令牌签名，直接在浏览器打开会被拒绝；'
                '请使用下方的「下载到本机」按钮，App 会带签名下载并保存到本机存储。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
          if (onDownload != null)
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                onDownload();
              },
              icon: const Icon(Icons.download_outlined, size: 18),
              label: const Text('下载到本机'),
            ),
        ],
      );
    },
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.copyable = false,
  });

  final String label;
  final String value;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SelectableText(
                  value,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              if (copyable)
                A11yIconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '复制$label',
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: value));
                    if (context.mounted) showSuccessSnack(context, '已复制');
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}
