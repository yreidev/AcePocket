import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/app_snack.dart';

/// 只读代码块：等宽字体、横向可滚动、可一键复制。
///
/// 用于展示模板的 docker compose 内容。
///
/// 纵向滚动持有**自己的** [ScrollController] 并交给 [Scrollbar]：
/// 本组件嵌在页面的 ListView 里，若两者都走 PrimaryScrollController，
/// 滚动条会绑到外层列表上（甚至因一个 controller 挂了两个 position 而报错）。
class CodeBlock extends StatefulWidget {
  const CodeBlock({
    super.key,
    required this.code,
    this.maxHeight = 360,
    this.copyLabel = '复制内容',
  });

  final String code;
  final double maxHeight;
  final String copyLabel;

  @override
  State<CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<CodeBlock> {
  final ScrollController _verticalController = ScrollController();

  @override
  void dispose() {
    _verticalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          constraints: BoxConstraints(maxHeight: widget.maxHeight),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Scrollbar(
            controller: _verticalController,
            child: SingleChildScrollView(
              controller: _verticalController,
              primary: false,
              padding: const EdgeInsets.all(10),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SelectableText(
                  widget.code.isEmpty ? '（内容为空）' : widget.code,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: widget.code.isEmpty
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: widget.code));
                    if (context.mounted) {
                      showSuccessSnack(context, '已复制到剪贴板');
                    }
                  },
            icon: const Icon(Icons.copy_all_outlined, size: 18),
            label: Text(widget.copyLabel),
          ),
        ),
      ],
    );
  }
}
