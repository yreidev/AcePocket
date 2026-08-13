import 'package:flutter/material.dart';

/// 全局 Material 3 主题（深浅色），种子色为稳重的蓝绿色。
class AppTheme {
  const AppTheme._();

  /// 品牌种子色：深青绿。
  static const Color seedColor = Color(0xFF00696E);

  static ThemeData get light => _build(Brightness.light);

  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      pageTransitionsTheme: _pageTransitions,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 2,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        space: 1,
        thickness: 1,
      ),
      listTileTheme: const ListTileThemeData(
        visualDensity: VisualDensity.compact,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.secondaryContainer,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
      ),
    );
  }

  /// 页面转场。
  ///
  /// Android 用 [PredictiveBackPageTransitionsBuilder]：Android 14+ 上返回手势
  /// 会实时跟手缩放当前页、露出目的页，滑到一半松手可取消；低版本自动退化为
  /// FadeForwards。它需要 `AndroidManifest.xml` 里的
  /// `android:enableOnBackInvokedCallback="true"` 才会收到系统的手势进度事件。
  ///
  /// 这里显式写死而不是依赖 Flutter 默认值：Android 默认转场在近几个大版本里
  /// 换过三次（Zoom → FadeForwards → PredictiveBack），升级 SDK 时不应该
  /// 悄悄改变返回手势的观感。本项目只发布 Android，其余平台留给框架兜底。
  static const PageTransitionsTheme _pageTransitions = PageTransitionsTheme(
    builders: <TargetPlatform, PageTransitionsBuilder>{
      TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
    },
  );
}
