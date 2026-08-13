import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/app_snack.dart';

/// 创建分享的表单结果（对应 `POST /api/file_share` 的请求字段）。
typedef ShareCreateResult = ({String path, int expireHours, int maxDownloads});

/// 创建文件分享对话框。
///
/// [initialPath] 为待分享文件的绝对路径；[pathEditable] 为 false 时锁定路径
/// （从文件列表进入时无需再改）。
Future<ShareCreateResult?> showShareCreateDialog(
  BuildContext context, {
  String initialPath = '',
  bool pathEditable = true,
}) {
  return showDialog<ShareCreateResult>(
    context: context,
    builder: (context) => _ShareCreateDialog(
      initialPath: initialPath,
      pathEditable: pathEditable,
    ),
  );
}

class _ShareCreateDialog extends StatefulWidget {
  const _ShareCreateDialog({
    required this.initialPath,
    required this.pathEditable,
  });

  final String initialPath;
  final bool pathEditable;

  @override
  State<_ShareCreateDialog> createState() => _ShareCreateDialogState();
}

class _ShareCreateDialogState extends State<_ShareCreateDialog> {
  static const _expireOptions = <(String, int)>[
    ('1 小时', 1),
    ('1 天', 24),
    ('7 天', 168),
    ('30 天', 720),
  ];

  late final TextEditingController _pathController;
  late final TextEditingController _expireController;
  late final TextEditingController _maxController;
  int? _preset = 24;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pathController = TextEditingController(text: widget.initialPath);
    _expireController = TextEditingController(text: '24');
    _maxController = TextEditingController(text: '0');
  }

  @override
  void dispose() {
    _pathController.dispose();
    _expireController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  void _submit() {
    final path = _pathController.text.trim();
    if (path.isEmpty || !path.startsWith('/')) {
      setState(() => _error = '请输入要分享的文件绝对路径');
      return;
    }
    final expire = int.tryParse(_expireController.text.trim()) ?? 0;
    if (expire < 1 || expire > 8760) {
      setState(() => _error = '有效期需在 1 - 8760 小时之间');
      return;
    }
    final max = int.tryParse(_maxController.text.trim()) ?? 0;
    if (max < 0) {
      setState(() => _error = '最大下载次数不能为负数');
      return;
    }
    Navigator.of(context)
        .pop((path: path, expireHours: expire, maxDownloads: max));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('创建分享'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _pathController,
                readOnly: !widget.pathEditable,
                maxLines: 2,
                minLines: 1,
                decoration: InputDecoration(
                  labelText: '文件路径',
                  helperText:
                      widget.pathEditable ? '仅支持分享文件，不能分享目录' : '路径来自所选文件，不可修改',
                  helperMaxLines: 2,
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  for (final option in _expireOptions)
                    ChoiceChip(
                      label: Text(option.$1),
                      selected: _preset == option.$2,
                      onSelected: (_) => setState(() {
                        _preset = option.$2;
                        _expireController.text = '${option.$2}';
                        _error = null;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _expireController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: const InputDecoration(
                        labelText: '有效期（小时）',
                      ),
                      onChanged: (value) => setState(() {
                        _preset = int.tryParse(value);
                        _error = null;
                      }),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _maxController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: const InputDecoration(
                        labelText: '最大下载次数',
                        helperText: '0 为不限',
                      ),
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('创建')),
      ],
    );
  }
}

/// 展示分享创建成功后的下载链接，并提供复制按钮。
Future<void> showShareLinkDialog(
  BuildContext context, {
  required String url,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        // 链接较长时（带访问入口的地址）内容区可滚动，避免溢出。
        scrollable: true,
        title: const Text('分享链接'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SelectableText(
              url,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Text(
              '该链接无需登录即可下载，请谨慎分发。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (!context.mounted) return;
              // 必须先弹提示再关对话框：pop 之后本 context 已失活，
              // showSuccessSnack 会因 !context.mounted 直接返回，提示就丢了。
              // SnackBar 挂在上层 ScaffoldMessenger 上，不随对话框一起消失。
              showSuccessSnack(context, '下载链接已复制到剪贴板');
              Navigator.of(context).pop();
            },
            icon: const Icon(Icons.copy_all_outlined),
            label: const Text('复制链接'),
          ),
        ],
      );
    },
  );
}
