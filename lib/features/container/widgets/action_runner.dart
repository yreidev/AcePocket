import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/widgets/app_snack.dart';

/// 执行一个耗时操作：期间展示不可取消的进度对话框，
/// 成功后弹出 [success] 提示，失败弹出错误提示。返回是否成功。
///
/// 进度对话框是模态且不可取消的，因此在操作在途期间调用方的按钮
/// 无需再自行防重复点击。
///
/// 危险操作请先用 core 的 `showConfirmDialog` 二次确认。
Future<bool> runAction(
  BuildContext context, {
  required String pending,
  required Future<void> Function() action,
  String? success,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);

  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => _ProgressDialog(message: pending),
    ),
  );

  Object? failure;
  try {
    await action();
  } catch (error) {
    failure = error;
  }

  if (navigator.mounted && navigator.canPop()) navigator.pop();

  // 提示统一走 core 的 app_snack（成对配色，深浅主题下均满足对比度）；
  // context 已失效时其内部会直接跳过。
  if (failure != null) {
    if (context.mounted) showErrorSnack(context, failure);
    return false;
  }
  if (success != null && context.mounted) showSuccessSnack(context, success);
  return true;
}

class _ProgressDialog extends StatelessWidget {
  const _ProgressDialog({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: theme.colorScheme.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 16),
              Flexible(
                child: Text(
                  message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
