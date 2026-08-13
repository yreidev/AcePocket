import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

/// 终端快捷键条：手机软键盘缺失的按键（Esc / Tab / 方向键 / Ctrl 组合 / 常用符号）。
///
/// - 功能键通过 [onKey] 交给 xterm 生成序列（会区分光标应用模式）；
/// - Ctrl 组合与符号通过 [onText] 直接写入 PTY 输入。
///
/// 无障碍：每个键帽不小于 48×48dp（Material 触摸目标下限），并带语义名称
/// （纯图标的方向键靠 `tooltip` 提供读屏名称，否则 TalkBack 只会念「按钮」）。
/// 键帽高度随系统字号放大，避免大字号下键帽文字被裁。
class TerminalKeyboardBar extends StatelessWidget {
  const TerminalKeyboardBar({
    super.key,
    required this.onKey,
    required this.onText,
    required this.onCtrl,
    required this.enabled,
  });

  /// 功能键（Esc / Tab / 方向键 / Home / End / PgUp / PgDn / Del）。
  final void Function(TerminalKey key) onKey;

  /// 原始文本（符号等）。
  final void Function(String text) onText;

  /// Ctrl + 字母（传入单个字母，如 `C`）。
  final void Function(String letter) onCtrl;

  /// 未连接时禁用。
  final bool enabled;

  /// 键帽最小高度 / 宽度：Material 无障碍触摸目标下限。
  static const double minKeySize = 48;

  /// 键帽上下留白（ListView 的 vertical padding，上下各一份）。
  static const double _verticalPadding = 6;

  static const List<(String, String)> _ctrlCombos = [
    ('C', '中断当前命令'),
    ('D', '结束输入 / 退出'),
    ('Z', '挂起到后台'),
    ('L', '清屏'),
    ('A', '移到行首'),
    ('E', '移到行尾'),
    ('U', '删除到行首'),
    ('K', '删除到行尾'),
    ('W', '删除前一个单词'),
    ('R', '搜索历史命令'),
  ];

  /// 符号键：(字符, 读屏名称)。纯符号对读屏很不友好（`|` 只会念「竖线」
  /// 或直接跳过），这里补中文名称。
  static const List<(String, String)> _symbols = [
    ('/', '斜杠'),
    ('-', '连字符'),
    ('_', '下划线'),
    ('|', '竖线（管道）'),
    ('~', '波浪号（家目录）'),
    ('.', '点'),
    ('*', '星号（通配）'),
    (r'$', '美元符'),
    ('&', '与号（后台运行）'),
    ('>', '大于号（重定向）'),
    ('<', '小于号（输入重定向）'),
    (':', '冒号'),
    ('"', '双引号'),
    ("'", '单引号'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 键帽高度随系统字号增长：labelLarge 约 14sp，放大后连同上下内边距一起长高，
    // 保证文字完整显示；下限仍为 48dp 触摸目标。
    final keyHeight = math.max(
      minKeySize,
      MediaQuery.textScalerOf(context).scale(20) + 28,
    );

    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: keyHeight + _verticalPadding * 2,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: _verticalPadding,
            ),
            children: [
              _CtrlMenuButton(enabled: enabled, onCtrl: onCtrl),
              _KeyChip(
                label: 'Esc',
                tooltip: 'Esc 退出键',
                enabled: enabled,
                onTap: () => onKey(TerminalKey.escape),
              ),
              _KeyChip(
                label: 'Tab',
                tooltip: 'Tab 补全',
                enabled: enabled,
                onTap: () => onKey(TerminalKey.tab),
              ),
              _KeyChip(
                label: '^C',
                tooltip: 'Ctrl+C 中断当前命令',
                emphasized: true,
                enabled: enabled,
                onTap: () => onCtrl('C'),
              ),
              _KeyChip(
                icon: Icons.keyboard_arrow_up,
                tooltip: '方向键 上（上一条历史命令）',
                enabled: enabled,
                onTap: () => onKey(TerminalKey.arrowUp),
              ),
              _KeyChip(
                icon: Icons.keyboard_arrow_down,
                tooltip: '方向键 下（下一条历史命令）',
                enabled: enabled,
                onTap: () => onKey(TerminalKey.arrowDown),
              ),
              _KeyChip(
                icon: Icons.keyboard_arrow_left,
                tooltip: '方向键 左（光标左移）',
                enabled: enabled,
                onTap: () => onKey(TerminalKey.arrowLeft),
              ),
              _KeyChip(
                icon: Icons.keyboard_arrow_right,
                tooltip: '方向键 右（光标右移）',
                enabled: enabled,
                onTap: () => onKey(TerminalKey.arrowRight),
              ),
              _KeyChip(
                label: 'Home',
                tooltip: 'Home 移到行首',
                enabled: enabled,
                onTap: () => onKey(TerminalKey.home),
              ),
              _KeyChip(
                label: 'End',
                tooltip: 'End 移到行尾',
                enabled: enabled,
                onTap: () => onKey(TerminalKey.end),
              ),
              _KeyChip(
                label: 'PgUp',
                tooltip: 'PgUp 向上翻页',
                enabled: enabled,
                onTap: () => onKey(TerminalKey.pageUp),
              ),
              _KeyChip(
                label: 'PgDn',
                tooltip: 'PgDn 向下翻页',
                enabled: enabled,
                onTap: () => onKey(TerminalKey.pageDown),
              ),
              _KeyChip(
                label: 'Del',
                tooltip: 'Del 删除光标后一个字符',
                enabled: enabled,
                onTap: () => onKey(TerminalKey.delete),
              ),
              for (final (symbol, name) in _symbols)
                _KeyChip(
                  label: symbol,
                  tooltip: '输入 $name',
                  enabled: enabled,
                  onTap: () => onText(symbol),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ctrl 组合键下拉。
class _CtrlMenuButton extends StatelessWidget {
  const _CtrlMenuButton({required this.enabled, required this.onCtrl});

  final bool enabled;
  final void Function(String letter) onCtrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: PopupMenuButton<String>(
        enabled: enabled,
        tooltip: '打开 Ctrl 组合键菜单',
        position: PopupMenuPosition.over,
        onSelected: (letter) {
          HapticFeedback.selectionClick();
          onCtrl(letter);
        },
        itemBuilder: (context) => [
          for (final combo in TerminalKeyboardBar._ctrlCombos)
            PopupMenuItem<String>(
              value: combo.$1,
              child: Row(
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 56),
                    child: Text(
                      'Ctrl+${combo.$1}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Flexible + 省略号：大字号下说明文字不会撑破菜单项。
                  Flexible(
                    child: Text(
                      combo.$2,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
        child: Container(
          alignment: Alignment.center,
          constraints: const BoxConstraints(
            minWidth: TerminalKeyboardBar.minKeySize,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: enabled
                ? theme.colorScheme.secondaryContainer
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Ctrl',
                  maxLines: 1,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: enabled
                        ? theme.colorScheme.onSecondaryContainer
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Icon(
                  Icons.arrow_drop_down,
                  size: 18,
                  color: enabled
                      ? theme.colorScheme.onSecondaryContainer
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 单个按键。
///
/// 高度由外层 [TerminalKeyboardBar] 的横向 [ListView] 拉满（≥48dp），
/// 宽度不小于 48dp；[tooltip] 同时作为长按提示与读屏名称。
class _KeyChip extends StatelessWidget {
  const _KeyChip({
    this.label,
    this.icon,
    required this.tooltip,
    this.emphasized = false,
    required this.enabled,
    required this.onTap,
  });

  final String? label;
  final IconData? icon;

  /// 长按提示 + 读屏名称，必填。
  final String tooltip;

  final bool emphasized;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final background = !enabled
        ? scheme.surfaceContainerHighest
        : emphasized
            ? scheme.errorContainer
            : scheme.surfaceContainer;
    final foreground = !enabled
        ? scheme.onSurfaceVariant.withValues(alpha: 0.5)
        : emphasized
            ? scheme.onErrorContainer
            : scheme.onSurface;

    final content = Container(
      constraints: const BoxConstraints(
        minWidth: TerminalKeyboardBar.minKeySize,
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      // 语义交给外层的 tooltip 名称，避免读屏把 `^C`、`~` 之类的键面
      // 字符再念一遍。
      child: ExcludeSemantics(
        child: icon != null
            ? Icon(icon, size: 20, color: foreground)
            // FittedBox：极端字号下宁可缩小也不裁切。
            : FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label ?? '',
                  maxLines: 1,
                  softWrap: false,
                  style:
                      theme.textTheme.labelLarge?.copyWith(color: foreground),
                ),
              ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 600),
        // 语义名称由下面的 Semantics 提供，避免 TalkBack 重复播报。
        excludeFromSemantics: true,
        child: MergeSemantics(
          child: Semantics(
            label: tooltip,
            button: true,
            enabled: enabled,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: enabled
                  ? () {
                      HapticFeedback.selectionClick();
                      onTap();
                    }
                  : null,
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}
