/// 统一的 SnackBar 提示。
///
/// 历史问题：多个模块的错误提示只把 `backgroundColor` 改成 `errorContainer`，
/// `content` 是裸 `Text`，前景色沿用 SnackBar 默认的 `onInverseSurface`——
/// 浅色主题下近白字浮在浅粉底（对比度约 1.1:1），深色主题下深灰字浮在深红底，
/// 用户根本看不清错误原因。这里所有配色都成对取自 [ColorScheme]
/// （`errorContainer` / `onErrorContainer`、`inverseSurface` / `onInverseSurface`），
/// Material 3 保证这两组配对在深浅主题下均满足对比度要求。
///
/// 用法：
/// ```dart
/// try {
///   await repo.doSomething();
///   if (context.mounted) showSuccessSnack(context, '保存成功');
/// } catch (e) {
///   if (context.mounted) showErrorSnack(context, e);
/// }
/// ```
library;

import 'package:flutter/material.dart';

import '../api/api_exception.dart';

/// 错误提示：`errorContainer` 底 + `onErrorContainer` 字与图标 + 关闭按钮。
///
/// [error] 可传任意对象，文案经 `describeError` 提取
/// （`ApiException` 取 `message`，其他异常去掉 `XxxException: ` 前缀）。
/// 展示 6 秒——错误信息通常较长，默认 4 秒读不完。
void showErrorSnack(BuildContext context, Object error) {
  final colorScheme = Theme.of(context).colorScheme;
  _show(
    context,
    message: describeError(error),
    icon: Icons.error_outline,
    background: colorScheme.errorContainer,
    foreground: colorScheme.onErrorContainer,
    duration: const Duration(seconds: 6),
    showCloseIcon: true,
  );
}

/// 成功提示：沿用 SnackBar 默认的 `inverseSurface` 底 + `onInverseSurface` 字，
/// 以对比度最高的 `inversePrimary` 勾选图标区分。
void showSuccessSnack(BuildContext context, String message) {
  final colorScheme = Theme.of(context).colorScheme;
  _show(
    context,
    message: message,
    icon: Icons.check_circle_outline,
    background: colorScheme.inverseSurface,
    foreground: colorScheme.onInverseSurface,
    iconColor: colorScheme.inversePrimary,
    duration: const Duration(seconds: 3),
  );
}

/// 普通信息提示：`inverseSurface` 底 + `onInverseSurface` 字。
void showInfoSnack(BuildContext context, String message) {
  final colorScheme = Theme.of(context).colorScheme;
  _show(
    context,
    message: message,
    icon: Icons.info_outline,
    background: colorScheme.inverseSurface,
    foreground: colorScheme.onInverseSurface,
    duration: const Duration(seconds: 4),
  );
}

/// 三种提示共用的构造：图标 + 文案 + 成对前景/背景色。
///
/// 文案最多 4 行并省略溢出——面板返回的错误 msg 偶尔很长，
/// 不限行数会把 SnackBar 撑到占满半屏。
void _show(
  BuildContext context, {
  required String message,
  required IconData icon,
  required Color background,
  required Color foreground,
  required Duration duration,
  Color? iconColor,
  bool showCloseIcon = false,
}) {
  if (!context.mounted) return;
  final theme = Theme.of(context);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: background,
        showCloseIcon: showCloseIcon,
        closeIconColor: foreground,
        duration: duration,
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: iconColor ?? foreground),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
}
