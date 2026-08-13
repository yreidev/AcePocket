import 'package:flutter/material.dart';

import '../../../core/widgets/a11y.dart';

/// 以底部弹层展示一个表单。
Future<T?> showDbSheet<T>(BuildContext context, Widget sheet) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.92,
    ),
    builder: (_) => sheet,
  );
}

/// 底部弹层表单骨架：标题栏 + 可滚动内容 + 底部提交按钮。
class DbSheet extends StatelessWidget {
  const DbSheet({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.onSubmit,
    this.submitText = '提交',
    this.submitting = false,
  });

  final String title;
  final String? subtitle;

  /// 表单内容，相邻项之间自动加 12px 间距。
  final List<Widget> children;

  /// 提交回调；为 null 时按钮禁用。
  final VoidCallback? onSubmit;

  final String submitText;
  final bool submitting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            // 副标题常是「数据库：<很长的库名>」，限行避免顶栏被撑高。
                            subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  A11yIconButton(
                    tooltip: '关闭表单',
                    onPressed: submitting
                        ? null
                        : () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < children.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      children[i],
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: FilledButton(
                onPressed: submitting ? null : onSubmit,
                child: submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : Text(submitText),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 弹层里的提示条。
class SheetHint extends StatelessWidget {
  const SheetHint(
      {super.key, required this.text, this.icon = Icons.info_outline});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 带「随机生成」按钮的密码输入框。
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    this.label = '密码',
    this.hint,
    this.onGenerate,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;

  /// 点击「生成」时调用，返回生成的密码；为 null 时不显示生成按钮。
  final String Function()? onGenerate;

  final bool enabled;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      enabled: widget.enabled,
      obscureText: _obscure,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            A11yIconButton(
              tooltip: _obscure ? '显示密码' : '隐藏密码',
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: Icon(
                _obscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 20,
              ),
            ),
            if (widget.onGenerate != null)
              A11yIconButton(
                tooltip: '随机生成密码',
                onPressed: widget.enabled
                    ? () {
                        widget.controller.text = widget.onGenerate!();
                        setState(() => _obscure = false);
                      }
                    : null,
                icon: const Icon(Icons.casino_outlined, size: 20),
              ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}
