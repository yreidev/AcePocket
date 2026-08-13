import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../models/user_token.dart';
import 'format_utils.dart';
import 'setting_fields.dart';

/// 令牌编辑对话框的返回结果。
class TokenEditorResult {
  const TokenEditorResult({required this.ips, required this.expiredAt});

  /// IP 白名单（支持 CIDR），空表示不限制。
  final List<String> ips;

  /// 过期时间（面板要求晚于当前时间且早于 10 年后）。
  final DateTime expiredAt;
}

/// 创建 / 编辑 API 令牌对话框。[token] 为空表示创建。
Future<TokenEditorResult?> showTokenEditorDialog(
  BuildContext context, {
  UserToken? token,
}) {
  return showDialog<TokenEditorResult>(
    context: context,
    builder: (context) => _TokenEditorDialog(token: token),
  );
}

class _TokenEditorDialog extends StatefulWidget {
  const _TokenEditorDialog({this.token});

  final UserToken? token;

  @override
  State<_TokenEditorDialog> createState() => _TokenEditorDialogState();
}

class _TokenEditorDialogState extends State<_TokenEditorDialog> {
  /// 预设有效期（天）。0 表示自定义日期。
  static const Map<int, String> _presets = {
    7: '7 天',
    30: '30 天',
    90: '90 天',
    365: '1 年',
    3650: '10 年',
    0: '自定义日期',
  };

  late List<String> _ips;
  late int _presetDays;
  late DateTime _expiredAt;

  @override
  void initState() {
    super.initState();
    _ips = List<String>.from(widget.token?.ips ?? const <String>[]);
    final existing = widget.token?.expiredAt;
    if (existing != null && existing.isAfter(DateTime.now())) {
      _presetDays = 0;
      _expiredAt = existing;
    } else {
      _presetDays = 365;
      _expiredAt = DateTime.now().add(const Duration(days: 365));
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiredAt.isAfter(now) ? _expiredAt : now,
      firstDate: now.add(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 3650)),
      helpText: '选择过期日期',
    );
    if (picked == null) return;
    setState(() {
      _presetDays = 0;
      // 统一取当天 23:59:59，避免选当天时刚好早于当前时间被服务端拒绝。
      _expiredAt = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCreate = widget.token == null;
    return AlertDialog(
      title: Text(isCreate ? '创建 API 令牌' : '编辑令牌 #${widget.token!.id}'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SettingDropdown<int>(
                label: '有效期',
                value: _presetDays,
                items: _presets,
                onChanged: (days) {
                  if (days == 0) {
                    setState(() => _presetDays = 0);
                    _pickDate();
                    return;
                  }
                  setState(() {
                    _presetDays = days;
                    _expiredAt = DateTime.now().add(Duration(days: days));
                  });
                },
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '过期时间：${formatDateTime(_expiredAt)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    TextButton(onPressed: _pickDate, child: const Text('选择日期')),
                  ],
                ),
              ),
              StringListField(
                label: 'IP 白名单',
                values: _ips,
                hint: '如 192.0.2.10 或 10.0.0.0/8',
                helper: '留空表示不限制来源 IP，支持 CIDR',
                onChanged: (v) => setState(() => _ips = v),
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
            if (!_expiredAt.isAfter(DateTime.now())) {
              showErrorSnack(context, '过期时间必须晚于当前时间');
              return;
            }
            Navigator.of(
              context,
            ).pop(TokenEditorResult(ips: _ips, expiredAt: _expiredAt));
          },
          child: Text(isCreate ? '创建' : '保存'),
        ),
      ],
    );
  }
}

/// 创建成功后展示令牌明文（仅此一次）。
Future<void> showTokenCreatedDialog(BuildContext context, UserToken token) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      final theme = Theme.of(context);
      final secret = token.token ?? '';
      return AlertDialog(
        title: const Text('创建成功'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: theme.colorScheme.onErrorContainer,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '令牌仅在此处显示一次，关闭后无法再次查看，请立即复制保存。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _CopyableField(label: '令牌 ID', value: '${token.id}'),
                const SizedBox(height: 12),
                _CopyableField(label: '令牌', value: secret, multiline: true),
                const SizedBox(height: 12),
                Text(
                  '过期时间：${formatDateTime(token.expiredAt)}\n'
                  'IP 白名单：${token.ips.isEmpty ? '不限制' : token.ips.join('，')}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '在本 App 中添加服务器时，「令牌 ID」与「令牌」需分别填写。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: 'ID: ${token.id}\nToken: $secret'),
              );
              if (!context.mounted) return;
              showSuccessSnack(context, '已复制令牌 ID 与令牌');
            },
            child: const Text('复制全部'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('我已保存'),
          ),
        ],
      );
    },
  );
}

class _CopyableField extends StatelessWidget {
  const _CopyableField({
    required this.label,
    required this.value,
    this.multiline = false,
  });

  final String label;
  final String value;
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  value.isEmpty ? '-' : value,
                  maxLines: multiline ? 4 : 1,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
            A11yIconButton(
              tooltip: '复制$label',
              icon: const Icon(Icons.copy_outlined, size: 18),
              onPressed: value.isEmpty
                  ? null
                  : () async {
                      await Clipboard.setData(ClipboardData(text: value));
                      if (!context.mounted) return;
                      showSuccessSnack(context, '已复制$label');
                    },
            ),
          ],
        ),
      ],
    );
  }
}
