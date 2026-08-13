import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/lifecycle/app_lifecycle.dart';
import 'core/router/router.dart';
import 'core/theme/theme.dart';
import 'features/app_settings/repo/app_settings_store.dart';
import 'features/app_update/providers/app_update_providers.dart';
import 'features/app_update/repo/apk_installer.dart';
import 'features/app_update/widgets/update_dialog.dart';
import 'features/panel_users/two_factor.dart';
import 'features/settings/providers/appearance_providers.dart';

/// 应用根组件：MaterialApp.router + Material 3 深浅色主题 + 简体中文。
class AcePanelApp extends ConsumerStatefulWidget {
  const AcePanelApp({super.key});

  @override
  ConsumerState<AcePanelApp> createState() => _AcePanelAppState();
}

class _AcePanelAppState extends ConsumerState<AcePanelApp> {
  /// 启动后延迟触发的自动更新检查定时器；dispose 时取消，
  /// 避免 widget 测试因 pending timer 挂起。
  Timer? _autoUpdateTimer;

  @override
  void initState() {
    super.initState();
    // 注册全局登录挑战处理器：面板账号开启两步验证 / 面板要求图形验证码时，
    // 任何 wsConnect（终端、容器日志、证书签发、迁移进度、面板升级…）
    // 都会自动弹出输入框。见 core/api/ws_client.dart 的 WsSessionManager。
    installWsLoginChallengeHandler();
    // 提前实例化应用生命周期状态源（core/lifecycle/app_lifecycle.dart），
    // 使 AppLifecycleListener 从应用启动起就开始监听前台 / 后台切换，
    // 供首页轮询、终端心跳、迁移重连等周期性任务在后台时暂停。
    ref.read(appForegroundProvider);
    // 启动后延迟自动检查更新（不阻塞首帧）；可在「应用设置」中关闭。
    if (supportsInAppUpdate && AppSettingsStore.instance.autoCheckUpdate) {
      _autoUpdateTimer = Timer(const Duration(seconds: 5), _autoCheckUpdate);
    }
  }

  @override
  void dispose() {
    _autoUpdateTimer?.cancel();
    super.dispose();
  }

  /// 启动时静默检查更新：仅在发现新版本且用户未跳过该版本时弹窗，
  /// 已是最新 / 检查失败（含无网络）一律静默，不打扰用户。
  Future<void> _autoCheckUpdate() async {
    try {
      final result = await ref.read(appUpdateCheckerProvider).check();
      if (result.status != UpdateCheckStatus.updateAvailable) return;
      final release = result.release;
      if (release == null) return;
      if (release.version == AppSettingsStore.instance.skippedUpdateVersion) {
        return;
      }
      final context = rootNavigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      await showAppUpdateDialog(context, release);
    } catch (_) {
      // 自动检查全程兜底静默：任何异常都不影响正常使用。
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    // 主题模式由「应用设置」页设置并持久化（features/settings/providers/appearance_providers.dart）。
    final themeMode = ref.watch(appThemeModeProvider);
    return MaterialApp.router(
      title: 'AcePocket',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
