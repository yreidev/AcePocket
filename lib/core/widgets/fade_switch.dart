import 'package:flutter/material.dart';

import '../theme/motion.dart';

/// 内容切换时的交叉淡入。
///
/// 用于「同一个位置、内容整体换掉」的场景：加载中 ↔ 列表 ↔ 空态 ↔ 错误态、
/// 开关 ↔ 进度圈。直接 `if/else` 返回不同组件会让界面硬闪，接口稍慢时尤其明显。
///
/// 与直接用 [AnimatedSwitcher] 的区别：
/// - 时长与曲线取自 [AppMotion]，并跟随系统「移除动画」无障碍设置退化为瞬时；
/// - 淡出中的旧内容不再响应点击——切服务器时列表正在淡出，此刻点中旧条目会
///   跳到上一台机器的资源；
/// - [expand] 为 true 时新旧内容都撑满父级，避免整页占位在过渡期间尺寸跳动。
///
/// **[child] 必须带 [Key]**，否则 [AnimatedSwitcher] 认为内容没变、不触发过渡。
class FadeSwitch extends StatelessWidget {
  const FadeSwitch({
    super.key,
    required this.child,
    this.duration = AppMotion.stateSwap,
    this.expand = false,
  });

  final Widget child;

  final Duration duration;

  /// 是否让新旧内容都铺满父级约束。
  ///
  /// 整页占位（列表 / LoadingView / ErrorView）用 true；行内小控件保持 false，
  /// 按最大子节点尺寸居中即可。为 true 时父级必须提供有界约束。
  final bool expand;

  static Widget _expandLayout(
    Widget? currentChild,
    List<Widget> previousChildren,
  ) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        for (final previous in previousChildren) IgnorePointer(child: previous),
        ?currentChild,
      ],
    );
  }

  static Widget _looseLayout(
    Widget? currentChild,
    List<Widget> previousChildren,
  ) {
    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        for (final previous in previousChildren) IgnorePointer(child: previous),
        ?currentChild,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotion.resolve(context, duration),
      switchInCurve: AppMotion.enter,
      switchOutCurve: AppMotion.exit,
      layoutBuilder: expand ? _expandLayout : _looseLayout,
      child: child,
    );
  }
}
