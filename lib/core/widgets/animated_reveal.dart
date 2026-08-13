import 'package:flutter/material.dart';

import '../theme/motion.dart';
import 'fade_switch.dart';

/// 条件内容的展开 / 收起。
///
/// 用于「数据回来之后才出现」的通栏内容：面板健康横幅、版本不支持提示、
/// 新版本提示等。这些组件在无内容时返回 [SizedBox.shrink]，接口一返回就整块
/// 弹出来，把下方内容瞬间顶下去；反过来问题恢复时又瞬间塌陷。
///
/// 展开时先撑开高度、同时淡入；收起时先淡出、再收高度。高度由 [AnimatedSize]
/// 负责，并跟随系统「移除动画」设置退化为瞬时。
///
/// 只适合宽度由父级决定的通栏内容：隐藏态占位是一个 0 高、宽度撑满的盒子，
/// 因此收起过程中不会出现左右方向的抖动。
class AnimatedReveal extends StatelessWidget {
  const AnimatedReveal({
    super.key,
    required this.visible,
    required this.child,
    this.duration = AppMotion.stateSwap,
  });

  /// 是否展示 [child]。
  final bool visible;

  final Widget child;

  final Duration duration;

  static const Widget _collapsed = SizedBox(
    key: ValueKey<String>('reveal-collapsed'),
    width: double.infinity,
    height: 0,
  );

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: AppMotion.resolve(context, duration),
      curve: AppMotion.standard,
      alignment: Alignment.topCenter,
      child: FadeSwitch(
        duration: duration,
        child: visible
            ? KeyedSubtree(
                key: const ValueKey<String>('reveal-content'),
                child: child,
              )
            : _collapsed,
      ),
    );
  }
}

/// 展开 / 收起的指示箭头。
///
/// 直接在 `Icons.expand_more` 与 `Icons.expand_less` 之间硬换图标会闪一下，
/// 这里始终用同一个图标、旋转半圈，方向变化本身就说明了状态。
class ExpandChevron extends StatelessWidget {
  const ExpandChevron({
    super.key,
    required this.expanded,
    this.size,
    this.color,
  });

  final bool expanded;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return AnimatedRotation(
      turns: expanded ? 0.5 : 0,
      duration: AppMotion.resolve(context, AppMotion.control),
      curve: AppMotion.standard,
      child: Icon(Icons.expand_more, size: size, color: color),
    );
  }
}
