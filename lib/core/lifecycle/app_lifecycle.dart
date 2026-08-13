import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 应用是否处于前台（[AppLifecycleState.resumed]）。
///
/// 锁屏、切到其他应用（paused / hidden）以及失焦（inactive，如来电、
/// 系统弹窗、进入应用切换器）都视为「非前台」。首页轮询、终端心跳、
/// 迁移重连循环等周期性任务据此暂停，回到前台后再恢复，
/// 避免后台持续请求费电费流量。
///
/// 常驻 Provider（非 autoDispose）：在 `app.dart` 的根组件里读取一次即完成
/// 注册，之后由 [AppLifecycleListener] 持续驱动（Flutter 3.13+ 官方 API，
/// 内部即 WidgetsBindingObserver，无需手动 add/removeObserver）。
final appForegroundProvider = NotifierProvider<AppForegroundNotifier, bool>(
  AppForegroundNotifier.new,
);

/// 监听应用生命周期，把「是否前台」暴露为布尔状态。
class AppForegroundNotifier extends Notifier<bool> {
  AppLifecycleListener? _listener;

  @override
  bool build() {
    // 防御式处理：Notifier 重建（理论上无依赖不会发生）时不重复注册。
    _listener?.dispose();
    _listener = AppLifecycleListener(onStateChange: _onStateChange);
    ref.onDispose(() {
      _listener?.dispose();
      _listener = null;
    });
    // 首帧之前平台可能尚未上报生命周期（lifecycleState 为 null），按前台处理。
    final current = WidgetsBinding.instance.lifecycleState;
    return current == null || current == AppLifecycleState.resumed;
  }

  void _onStateChange(AppLifecycleState next) {
    state = next == AppLifecycleState.resumed;
  }
}
