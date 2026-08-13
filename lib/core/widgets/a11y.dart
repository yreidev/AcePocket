/// 无障碍（读屏 / 触摸目标）辅助封装。
///
/// 现状问题：项目里大量纯图标 [IconButton] 没有 `tooltip`，TalkBack 只会念
/// 「按钮」；列表项里的 [Switch] 对读屏是匿名的，盲用户双击可能停掉某个网站
/// 却不知道停的是哪一个。本文件提供三个极薄的封装，接入成本接近于零。
library;

import 'package:flutter/material.dart';

/// 带语义标签的图标按钮。
///
/// 与 [IconButton] 的唯一区别是 [tooltip] **必填**：它既是长按浮层文案，
/// 也是 TalkBack / VoiceOver 播报的按钮名称（Flutter 的 [Tooltip] 会把文案
/// 写进语义树）。因此文案要说清「按下会发生什么」，如「刷新列表」「删除备份」，
/// 而不是「刷新」这种单字动词。
///
/// 触摸目标不小于 48×48dp（[IconButton] 默认已满足，这里显式兜底，
/// 避免调用方传入紧凑的 `visualDensity` / `padding` 后跌破下限）。
class A11yIconButton extends StatelessWidget {
  const A11yIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
    this.iconSize,
    this.padding,
    this.visualDensity,
    this.style,
    this.isSelected,
    this.selectedIcon,
  });

  /// 图标控件，通常是 `Icon(Icons.refresh)`。
  final Widget icon;

  /// 无障碍名称 + 长按提示，必填。
  final String tooltip;

  /// 点击回调；传 null 则按钮禁用（语义上也会播报为已禁用）。
  final VoidCallback? onPressed;

  /// 图标颜色。
  final Color? color;

  /// 图标尺寸。
  final double? iconSize;

  /// 内边距。
  final EdgeInsetsGeometry? padding;

  /// 视觉密度。
  final VisualDensity? visualDensity;

  /// 按钮样式。
  final ButtonStyle? style;

  /// 切换态按钮的选中状态。
  final bool? isSelected;

  /// 选中时展示的图标。
  final Widget? selectedIcon;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      color: color,
      iconSize: iconSize,
      padding: padding,
      visualDensity: visualDensity,
      style: style,
      isSelected: isSelected,
      selectedIcon: selectedIcon,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      icon: icon,
    );
  }
}

/// 给开关补充语义标签。
///
/// [label] 说明**控制对象**（如「网站 example.com 的运行状态」），
/// 开 / 关状态由 [Switch] 自身播报，[label] 里不要再写「已开启」之类的状态词，
/// 否则读屏会念两遍且可能自相矛盾。
///
/// [child] 一般是 [Switch]（列表项 trailing）；若整行都可点，也可以包住整行。
/// 用 [MergeSemantics] 把标签与开关合并为一个可操作节点，读屏一次念完。
Widget a11ySwitch({required String label, required Widget child}) {
  return MergeSemantics(
    child: Semantics(container: true, label: label, child: child),
  );
}

/// 确保最小触摸目标 [size]×[size]dp（Material 无障碍下限为 48dp）。
///
/// 用于紧凑列表里的小图标、小徽标等本身尺寸不足但可点击的元素：
/// 只扩大命中区域与占位，不改变 [child] 的视觉大小。
Widget minTouchTarget({required Widget child, double size = 48}) {
  return ConstrainedBox(
    constraints: BoxConstraints(minWidth: size, minHeight: size),
    child: Center(widthFactor: 1, heightFactor: 1, child: child),
  );
}
