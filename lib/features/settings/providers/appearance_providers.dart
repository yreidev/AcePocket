import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App 外观偏好（主题模式）持久化。
///
/// 使用 shared_preferences（非敏感数据，与服务器凭据分离存储）。
class AppearanceStore {
  const AppearanceStore._();

  static const String themeModeKey = 'acepanel_theme_mode';

  static Future<ThemeMode> loadThemeMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return parse(prefs.getString(themeModeKey));
    } catch (_) {
      return ThemeMode.system;
    }
  }

  static Future<void> saveThemeMode(ThemeMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(themeModeKey, serialize(mode));
    } catch (_) {
      // 存储失败不影响当前会话的主题切换。
    }
  }

  static ThemeMode parse(String? raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String serialize(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}

/// App 主题模式（跟随系统 / 亮色 / 暗色）。
///
/// 首帧先返回 [ThemeMode.system]，随后异步读取本地偏好并刷新，
/// `app.dart` 只需 `themeMode: ref.watch(appThemeModeProvider)`。
final appThemeModeProvider = NotifierProvider<AppThemeModeNotifier, ThemeMode>(
  AppThemeModeNotifier.new,
);

class AppThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    _restore();
    return ThemeMode.system;
  }

  Future<void> _restore() async {
    final mode = await AppearanceStore.loadThemeMode();
    try {
      if (mode != state) state = mode;
    } catch (_) {
      // provider 已被销毁（如容器关闭），忽略。
    }
  }

  /// 切换主题模式并持久化。
  Future<void> setMode(ThemeMode mode) async {
    if (mode == state) return;
    state = mode;
    await AppearanceStore.saveThemeMode(mode);
  }
}

/// 主题模式的中文描述。
String themeModeLabel(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.light:
      return '亮色';
    case ThemeMode.dark:
      return '暗色';
    case ThemeMode.system:
      return '跟随系统';
  }
}
