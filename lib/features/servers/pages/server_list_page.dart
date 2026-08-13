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
import '../widgets/connection_test_dialog.dart';
import '../widgets/server_list_tile.dart';

/// 服务器列表：切换当前服务器、测试连接、编辑、删除。
///
/// 数据来源为 core 的 `serverListProvider` / `activeServerProvider`
/// （本地安全存储），因此没有服务端分页，仅提供下拉刷新（重新读取存储）。
class ServerListPage extends ConsumerWidget {
  const ServerListPage({super.key});

  Future<void> _switchTo(
    BuildContext context,
    WidgetRef ref,
    ServerConfig server,
  ) async {
    if (ref.read(activeServerProvider)?.id == server.id) return;
    await ref.read(activeServerProvider.notifier).select(server.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('已切换到「${server.name}」')));
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    ServerConfig server,
  ) async {
    final isActive = ref.read(activeServerProvider)?.id == server.id;
    final ok = await showConfirmDialog(
      context,
      title: '删除服务器',
      content: '确定要删除「${server.name}」吗？'
          '${isActive ? '\n它是当前选中的服务器，删除后将自动切换到其他服务器。' : ''}'
          '\n此操作仅移除本机保存的配置与令牌，不会影响面板本身。',
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
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final serversAsync = ref.watch(serverListProvider);
    final active = ref.watch(activeServerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('服务器管理'),
        actions: [
          A11yIconButton(
            icon: const Icon(Icons.add),
            tooltip: '添加服务器',
            onPressed: () => context.push('/servers/edit'),
          ),
        ],
      ),
      floatingActionButton: (serversAsync.valueOrNull ?? const []).isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push('/servers/edit'),
              icon: const Icon(Icons.add),
              label: const Text('添加'),
            ),
      body: serversAsync.when(
        loading: () => const LoadingView(message: '正在加载服务器列表…'),
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(serverListProvider),
        ),
        data: (servers) {
          if (servers.isEmpty) {
            return EmptyView(
              message: '还没有添加任何服务器',
              icon: Icons.dns_outlined,
              action: FilledButton.icon(
                onPressed: () => context.go('/servers/setup'),
                icon: const Icon(Icons.add),
                label: const Text('添加服务器'),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(serverListProvider);
              await ref.read(serverListProvider.future);
            },
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 8, bottom: 96),
              itemCount: servers.length + 1,
              itemBuilder: (context, index) {
                if (index == servers.length) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                    child: Text(
                      '共 ${servers.length} 台服务器。点击卡片可切换当前服务器，'
                      '所有配置与令牌仅保存在本机安全存储中。',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                final server = servers[index];
                return ServerListTile(
                  server: server,
                  isActive: active?.id == server.id,
                  onTap: () => _switchTo(context, ref, server),
                  onTest: () => showConnectionTestDialog(
                    context,
                    serverId: server.id,
                    serverName: server.name,
                  ),
                  onEdit: () => context.push('/servers/edit?id=${server.id}'),
                  onDelete: () => _delete(context, ref, server),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
