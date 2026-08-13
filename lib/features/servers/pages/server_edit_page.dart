import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/server.dart';
import '../../../core/storage/server_store.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../widgets/server_form.dart';

/// 添加 / 编辑服务器。
///
/// 路由：
/// - `/servers/edit` —— 添加；
/// - `/servers/edit?id=<uuid>` —— 编辑；
/// - `/servers/edit?id=<uuid>&advanced=1` —— 编辑并自动展开高级选项
///   （WebSocket 功能提示用户补填面板账号时使用）。
class ServerEditPage extends ConsumerWidget {
  const ServerEditPage({
    super.key,
    this.serverId,
    this.expandAdvanced = false,
  });

  /// 编辑时传入服务器 id；添加时为 null。
  final String? serverId;

  /// 是否进入即展开「高级选项」。
  final bool expandAdvanced;

  bool get _isEdit => serverId != null && serverId!.isNotEmpty;

  void _close(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/servers');
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    ServerConfig server,
  ) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除服务器',
      content: '确定要删除「${server.name}」吗？\n'
          '此操作仅移除本机保存的配置与令牌，不会影响面板本身。',
      confirmText: '删除',
      danger: true,
    );
    if (!ok) return;

    await ref.read(serverListProvider.notifier).remove(server.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('已删除「${server.name}」')));

    final remaining = ref.read(serverListProvider).valueOrNull ?? const [];
    if (remaining.isEmpty) {
      context.go('/servers/setup');
    } else {
      _close(context);
    }
  }

  ServerConfig? _findServer(List<ServerConfig> servers) {
    for (final s in servers) {
      if (s.id == serverId) return s;
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serversAsync = ref.watch(serverListProvider);

    final ServerConfig? initial = _isEdit
        ? _findServer(serversAsync.valueOrNull ?? const <ServerConfig>[])
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '编辑服务器' : '添加服务器'),
        actions: [
          if (initial != null)
            A11yIconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除服务器',
              onPressed: () => _delete(context, ref, initial),
            ),
        ],
      ),
      body: serversAsync.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(serverListProvider),
        ),
        data: (_) {
          if (_isEdit && initial == null) {
            return EmptyView(
              message: '未找到该服务器，可能已被删除',
              icon: Icons.search_off_outlined,
              action: FilledButton(
                onPressed: () => _close(context),
                child: const Text('返回'),
              ),
            );
          }
          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
              children: [
                ServerForm(
                  initial: initial,
                  submitLabel: '保存',
                  autoExpandAdvanced: expandAdvanced,
                  onSubmit: (config) async {
                    final notifier = ref.read(serverListProvider.notifier);
                    final isUpdate = initial != null;
                    if (isUpdate) {
                      await notifier.updateServer(config);
                    } else {
                      await notifier.add(config);
                    }
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(SnackBar(
                        content: Text(isUpdate
                            ? '已保存「${config.name}」'
                            : '已添加「${config.name}」'),
                      ));
                    _close(context);
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
