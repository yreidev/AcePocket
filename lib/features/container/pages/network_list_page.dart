import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/format.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../models/container_network.dart';
import '../models/json_utils.dart';
import '../providers/container_providers.dart';
import '../widgets/action_runner.dart';
import '../widgets/info_row.dart';
import '../widgets/network_create_sheet.dart';
import '../widgets/paged_list_view.dart';
import '../widgets/status_badge.dart';

/// 容器网络管理页（`/containers/network`）。
class NetworkListPage extends ConsumerWidget {
  const NetworkListPage({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final ok = await showNetworkCreateSheet(context);
    if (ok) {
      await ref.read(containerNetworksProvider.notifier).reload();
    }
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    ContainerNetwork network,
  ) async {
    if (network.isPredefined) {
      showInfoSnack(context, '「${network.name}」是容器引擎预置网络，不可删除');
      return;
    }
    final ok = await showConfirmDialog(
      context,
      title: '删除网络',
      content: '确定要删除网络「${network.name}」吗？\n仍连接该网络的容器会导致删除失败。',
      confirmText: '删除',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    final success = await runAction(
      context,
      pending: '正在删除网络…',
      success: '网络已删除',
      action: () => ref.read(containerRepoProvider).removeNetwork(network.id),
    );
    if (success) {
      await ref.read(containerNetworksProvider.notifier).reload();
    }
  }

  Future<void> _prune(BuildContext context, WidgetRef ref) async {
    final ok = await showConfirmDialog(
      context,
      title: '清理网络',
      content: '将删除所有未被任何容器使用的自定义网络。确定继续吗？',
      confirmText: '清理',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    final success = await runAction(
      context,
      pending: '正在清理未使用的网络…',
      success: '清理完成',
      action: () => ref.read(containerRepoProvider).pruneNetworks(),
    );
    if (success) {
      await ref.read(containerNetworksProvider.notifier).reload();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(containerNetworksProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('网络管理'),
        actions: [
          A11yIconButton(
            tooltip: '刷新网络列表',
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.read(containerNetworksProvider.notifier).reload(),
          ),
          A11yIconButton(
            tooltip: '清理未使用的网络',
            icon: const Icon(Icons.cleaning_services_outlined),
            onPressed: () => _prune(context, ref),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('创建网络'),
      ),
      body: PagedListView<ContainerNetwork>(
        state: state,
        loadingMessage: '正在加载网络列表…',
        emptyMessage: '还没有任何网络',
        emptyIcon: Icons.lan_outlined,
        emptyAction: FilledButton.icon(
          onPressed: () => _create(context, ref),
          icon: const Icon(Icons.add),
          label: const Text('创建网络'),
        ),
        onRefresh: () => ref.read(containerNetworksProvider.notifier).refresh(),
        onLoadMore: () =>
            ref.read(containerNetworksProvider.notifier).loadMore(),
        onRetry: () => ref.invalidate(containerNetworksProvider),
        itemBuilder: (context, network, _) => _NetworkTile(
          network: network,
          onDelete: () => _remove(context, ref, network),
        ),
      ),
    );
  }
}

class _NetworkTile extends StatelessWidget {
  const _NetworkTile({required this.network, required this.onDelete});

  final ContainerNetwork network;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              network.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                          const SizedBox(width: 8),
                          StatusBadge(
                            label:
                                network.driver.isEmpty ? '-' : network.driver,
                            tone: BadgeTone.info,
                            dense: true,
                          ),
                          if (network.isPredefined) ...[
                            const SizedBox(width: 6),
                            const StatusBadge(
                              label: '预置',
                              tone: BadgeTone.neutral,
                              dense: true,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (network.scope.isNotEmpty)
                            StatusBadge(
                              label: '作用域 ${network.scope}',
                              tone: BadgeTone.neutral,
                              dense: true,
                            ),
                          if (network.ipv6)
                            const StatusBadge(
                              label: 'IPv6',
                              tone: BadgeTone.neutral,
                              dense: true,
                            ),
                          if (network.internal)
                            const StatusBadge(
                              label: '内部网络',
                              tone: BadgeTone.warning,
                              dense: true,
                            ),
                          if (network.attachable)
                            const StatusBadge(
                              label: '可附加',
                              tone: BadgeTone.neutral,
                              dense: true,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                A11yIconButton(
                  // 预置网络的按钮为禁用态，tooltip 说明原因，
                  // 否则读屏用户只会听到「已禁用」而不知道为什么。
                  tooltip: network.isPredefined
                      ? '预置网络不可删除'
                      : '删除网络 ${network.name}',
                  icon: Icon(
                    Icons.delete_outline,
                    color: network.isPredefined
                        ? theme.colorScheme.outline
                        : theme.colorScheme.error,
                  ),
                  onPressed: network.isPredefined ? null : onDelete,
                ),
              ],
            ),
            if (network.subnets.isNotEmpty || network.gateways.isNotEmpty) ...[
              const SizedBox(height: 8),
              TagWrap(
                values: [
                  for (final subnet in network.subnets) '子网 $subnet',
                  for (final gateway in network.gateways) '网关 $gateway',
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.tag, size: 13, color: theme.colorScheme.outline),
                const SizedBox(width: 4),
                Text(
                  network.shortIdText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                    fontFamily: 'monospace',
                    fontFamilyFallback: const ['Courier'],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(Icons.schedule,
                    size: 13, color: theme.colorScheme.outline),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    formatDateTime(network.createdAt),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
