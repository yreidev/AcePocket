import 'package:flutter/material.dart';

/// 全局动效令牌。
///
/// 时长与曲线一律取 Material 3 的 [Durations] / [Easing]，不自己发明数值，
/// 保证各页面的节奏一致，也与 Flutter 内置组件（SnackBar、Switch、NavigationBar、
/// 页面转场）同源。
///
/// 所有自定义动画都要经过 [resolve]：系统无障碍设置里开启「移除动画」时
/// （TalkBack 用户、前庭功能障碍用户，以及开发者选项里把动画缩放调到 0 的设备）
/// 返回 [Duration.zero]，动画退化为瞬时切换而不是被拉长或卡住。
abstract final class AppMotion {
  /// 占位态之间的交叉淡入：加载 / 空 / 错误 / 内容列表。
  static const Duration stateSwap = Durations.short4;

  /// 底部导航切换 tab。
  static const Duration tabSwitch = Durations.medium1;

  /// 控件内部的形态切换：开关 ↔ 进度圈、图标互换、按钮文案变化。
  static const Duration control = Durations.short3;

  /// 入场（元素出现、展开）。
  static const Curve enter = Easing.emphasizedDecelerate;

  /// 出场（元素消失、收起）。
  static const Curve exit = Easing.emphasizedAccelerate;

  /// 位置 / 尺寸变化等无明确进出方向的过渡。
  static const Curve standard = Easing.standard;

  /// 按当前无障碍设置解析时长；开启「移除动画」时为 [Duration.zero]。
  static Duration resolve(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}
