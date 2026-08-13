import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../models/terminal_settings.dart';
import '../providers/terminal_providers.dart';

/// 弹出终端设置面板（字号 / 快捷键条 / 回滚行数 / 自动重连）。
Future<void> showTerminalSettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => const TerminalSettingsSheet(),
  );
}

/// 终端设置面板内容。
class TerminalSettingsSheet extends ConsumerWidget {
  const TerminalSettingsSheet({super.key});

  /// 回滚行数滑块的步进。
  static const int _scrollbackStep = 500;

  /// 「恢复默认」会一次性覆盖全部终端偏好，先二次确认。
  static Future<void> _confirmReset(
    BuildContext context,
    TerminalSettingsNotifier notifier,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '恢复默认设置',
      content: '字号、快捷键条、回滚行数与自动重连都会恢复为默认值。',
      confirmText: '恢复默认',
    );
    if (!confirmed) return;
    // 不弹 SnackBar：底部弹窗会把它遮住，面板里的滑块 / 开关本身就会
    // 立刻回到默认值，反馈是可见的。
    notifier.reset();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(terminalSettingsProvider);
    final notifier = ref.read(terminalSettingsProvider.notifier);

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.tune, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '终端设置',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: () => _confirmReset(context, notifier),
                  child: const Text('恢复默认'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // 字号
            Row(
              children: [
                Text('字体大小', style: theme.textTheme.titleSmall),
                const Spacer(),
                Text(
                  // 同时给出可调范围，避免用户不知道拖到头了没有。
                  '${settings.fontSize.toStringAsFixed(0)}'
                  '（${TerminalSettings.minFontSize.toStringAsFixed(0)}'
                  '~${TerminalSettings.maxFontSize.toStringAsFixed(0)}）',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                A11yIconButton(
                  tooltip: '减小终端字号',
                  onPressed: settings.fontSize > TerminalSettings.minFontSize
                      ? notifier.decreaseFontSize
                      : null,
                  icon: const Icon(Icons.text_decrease),
                ),
                Expanded(
                  child: Slider(
                    value: settings.fontSize,
                    min: TerminalSettings.minFontSize,
                    max: TerminalSettings.maxFontSize,
                    divisions: (TerminalSettings.maxFontSize -
                            TerminalSettings.minFontSize)
                        .round(),
                    label: settings.fontSize.toStringAsFixed(0),
                    semanticFormatterCallback: (value) =>
                        '终端字号 ${value.round()}',
                    onChanged: notifier.setFontSize,
                  ),
                ),
                A11yIconButton(
                  tooltip: '增大终端字号',
                  onPressed: settings.fontSize < TerminalSettings.maxFontSize
                      ? notifier.increaseFontSize
                      : null,
                  icon: const Icon(Icons.text_increase),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              // 预览用等宽字体并可横向滚动：大字号时不至于被省略号截断，
              // 用户能看到实际字形宽度。
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(
                  r'root@acepanel:~# echo 预览 12345',
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: settings.fontSize,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // SwitchListTile 自带 title / subtitle，读屏已能念出控制对象，
            // 无需再套 a11ySwitch（会重复播报）。
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: settings.showKeyboardBar,
              onChanged: notifier.setShowKeyboardBar,
              title: const Text('显示快捷键条'),
              subtitle: const Text('Esc / Tab / 方向键 / Ctrl 组合键'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: settings.autoReconnect,
              onChanged: notifier.setAutoReconnect,
              title: const Text('断线后自动重连一次'),
              subtitle: const Text('仅对已成功连接过的会话生效'),
            ),

            const SizedBox(height: 8),
            Row(
              children: [
                Text('回滚行数', style: theme.textTheme.titleSmall),
                const Spacer(),
                Text(
                  '${settings.scrollback}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            Slider(
              value: settings.scrollback.toDouble(),
              min: TerminalSettings.minScrollback.toDouble(),
              max: TerminalSettings.maxScrollback.toDouble(),
              // 每档 500 行；由常量算出，改动上下限时不用再手改档数。
              divisions: ((TerminalSettings.maxScrollback -
                          TerminalSettings.minScrollback) /
                      _scrollbackStep)
                  .round(),
              label: '${settings.scrollback}',
              semanticFormatterCallback: (value) => '回滚 ${value.round()} 行',
              onChanged: (value) => notifier.setScrollback(value.round()),
            ),
            Text(
              '回滚行数决定终端能向上翻多少行历史输出，'
              '修改后在下次打开终端时生效。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
