import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/motion.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/animated_reveal.dart';
import '../../../core/widgets/app_snack.dart';
import '../models/runtime_models.dart';

/// 单个协程的可展开条目：折叠时显示编号、状态与最内层调用，
/// 展开后以可横向滚动的等宽字体展示完整堆栈，并可一键复制。
class GoroutineTile extends StatefulWidget {
  const GoroutineTile({super.key, required this.info});

  final GoroutineInfo info;

  @override
  State<GoroutineTile> createState() => _GoroutineTileState();
}

class _GoroutineTileState extends State<GoroutineTile> {
  bool _expanded = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.info.raw));
    if (!mounted) return;
    showSuccessSnack(context, '已复制 goroutine ${widget.info.id} 的堆栈');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final info = widget.info;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      // 展开时同时变化的有两处：概要行的 maxLines 与下方完整堆栈面板。
      // 两处各自加动画会先跳后展，这里在卡片层用一个 AnimatedSize 统一收敛，
      // 内容被裁剪着「拉出来」，读起来是一次完整的展开。
      child: AnimatedSize(
        duration: AppMotion.resolve(context, AppMotion.stateSwap),
        curve: AppMotion.standard,
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 整行可点但读屏只会念到里面的文字，不会说明「点了会怎样」，
            // 用 hint 补上（label 留空，避免盖掉编号 / 状态 / 栈帧原文）。
            Semantics(
              hint: _expanded ? '收起完整堆栈' : '展开完整堆栈',
              child: InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '#${info.id}',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    info.state.isEmpty ? '未知状态' : info.state,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              info.topFrame.isEmpty ? '（无堆栈信息）' : info.topFrame,
                              maxLines: _expanded ? 3 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      A11yIconButton(
                        tooltip: '复制 goroutine ${info.id} 的堆栈',
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: _copy,
                      ),
                      ExpandChevron(
                        expanded: _expanded,
                        size: 20,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_expanded)
              Container(
                width: double.infinity,
                color: colorScheme.surfaceContainerHighest,
                padding: const EdgeInsets.all(12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SelectableText(
                    info.stack.isEmpty ? '（无堆栈信息）' : info.stack,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      height: 1.45,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
