import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/ws_client.dart';
import '../../../core/storage/server_store.dart';

/// WebSocket 会话认证失败时的统一提示。
///
/// 面板禁止 API 令牌用于 `/api/ws/*`（见 core/api/ws_client.dart），
/// 终端 / SSH / 实时日志等功能必须使用面板账号登录。任何功能模块在捕获
/// [WsAuthException] 后都可以调用本函数，引导用户到服务器配置里补填账号密码：
///
/// ```dart
/// try {
///   final channel = await wsConnect(server, '/ws/ssh');
/// } on WsAuthException catch (e) {
///   if (context.mounted) await showWsAuthDialog(context, ref, e);
/// }
/// ```
///
/// 用户选择「去填写」时跳转到 `/servers/edit?id=<当前服务器>&advanced=1`
/// （自动展开高级选项）。返回 true 表示用户选择了去填写。
Future<bool> showWsAuthDialog(
  BuildContext context,
  WidgetRef ref,
  Object error,
) async {
  final server = ref.read(activeServerProvider);
  final message = error is WsAuthException ? error.message : error.toString();
  final missing = server != null && !server.hasCredentials;

  final go = await showDialog<bool>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        icon: Icon(Icons.lock_outline, color: theme.colorScheme.primary),
        title: const Text('需要面板账号'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              missing
                  ? '终端、SSH、实时日志等功能通过 WebSocket 连接面板，'
                        '面板不允许使用 API 令牌进行 WebSocket 认证，'
                        '需要在服务器配置中填写面板用户名与密码。'
                  : '面板会话建立失败，请检查服务器配置中的面板账号与密码是否正确。',
              style: theme.textTheme.bodyMedium,
            ),
            if (message.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('知道了'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('去填写'),
          ),
        ],
      );
    },
  );

  if (go == true && context.mounted) {
    if (server != null) {
      unawaited(context.push('/servers/edit?id=${server.id}&advanced=1'));
    } else {
      unawaited(context.push('/servers'));
    }
    return true;
  }
  return false;
}
