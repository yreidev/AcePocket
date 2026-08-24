import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/not_installed_view.dart';
import '../models/container.dart';
import '../providers/container_providers.dart';
import '../widgets/action_runner.dart';
import '../widgets/container_actions.dart';
import '../widgets/container_tile.dart';
import '../widgets/paged_list_view.dart';

/// 容器列表页（`/containers`）。
///
/// 支持搜索（`GET /api/container/container/search`）、下拉刷新、分页、
/// 启动 / 停止 / 重启 / 暂停 / 恢复 / 强制终止 / 重命名 / 删除，
/// 以及跳转镜像、网络、存储卷、编排管理页。
class ContainerListPage extends ConsumerStatefulWidget {
  const ContainerListPage({super.key});

  @override
  ConsumerState<ContainerListPage> createState() => _ContainerListPageState();
}

class _ContainerListPageState extends ConsumerState<ContainerListPage> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    // 重建以刷新「清空」按钮的显隐。
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      ref.read(containerKeywordProvider.notifier).state = value.trim();
    });
  }

  Future<void> _handleAction(ContainerItem item, ContainerAction action) async {
    final ok = await performContainerAction(
      context,
      ref,
      id: item.id,
      name: item.name,
      action: action,
    );
    if (!ok) return;
    ref.invalidate(containerInspectProvider(item.id));
    await ref.read(containersProvider.notifier).reload();
  }

  Future<void> _prune() async {
    final ok = await showConfirmDialog(
      context,
      title: '清理容器',
      content: '将删除所有已停止的容器，此操作不可恢复。确定继续吗？',
      confirmText: '清理',
      danger: true,
    );
    if (!ok || !mounted) return;
    final success = await runAction(
      context,
      pending: '正在清理已停止的容器…',
      success: '清理完成',
      action: () => ref.read(containerRepoProvider).pruneContainers(),
    );
    if (success) {
      await ref.read(containersProvider.notifier).reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(containersProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('容器管理'),
        actions: [
          A11yIconButton(
            tooltip: '刷新容器列表',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(containersProvider.notifier).reload(),
          ),
          PopupMenuButton<String>(
            tooltip: '更多操作',
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'image':
                  context.push('/containers/image');
                  break;
                case 'network':
                  context.push('/containers/network');
                  break;
                case 'volume':
                  context.push('/containers/volume');
                  break;
                case 'compose':
                  context.push('/containers/compose');
                  break;
                case 'prune':
                  _prune();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'image',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.album_outlined),
                  title: Text('镜像管理'),
                ),
              ),
              const PopupMenuItem(
                value: 'network',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.lan_outlined),
                  title: Text('网络管理'),
                ),
              ),
              const PopupMenuItem(
                value: 'volume',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.storage_outlined),
                  title: Text('存储卷管理'),
                ),
              ),
              const PopupMenuItem(
                value: 'compose',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.dashboard_customize_outlined),
                  title: Text('编排管理'),
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'prune',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.cleaning_services_outlined,
                    color: theme.colorScheme.error,
                  ),
                  title: Text(
                    '清理已停止容器',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: '搜索容器名称',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : A11yIconButton(
                        tooltip: '清空搜索关键词',
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      ),
              ),
            ),
          ),
          const _QuickNavBar(),
          Expanded(child: _buildBody(state)),
        ],
      ),
    );
  }

  Widget _buildBody(AsyncValue<PagedState<ContainerItem>> state) {
    // 列表加载失败时探测容器引擎是否已安装：未安装展示专门空态
    // （而不是把面板的原始报错丢给用户）；探测失败则回退到通用错误视图。
    if (state.hasError && !state.isLoading) {
      final installed = ref.watch(containerEngineInstalledProvider);
      if (installed.value == false) {
        return NotInstalledView(
          title: '未安装容器引擎',
          message:
              '容器管理需要面板已安装 Docker（或 Podman）应用，'
              '请先到应用商店安装后再使用本功能。',
          icon: Icons.directions_boat_outlined,
          onRecheck: () {
            ref.invalidate(containerEngineInstalledProvider);
            ref.invalidate(containersProvider);
          },
        );
      }
    }
    return PagedListView<ContainerItem>(
      state: state,
      loadingMessage: '正在加载容器列表…',
      emptyMessage: ref.watch(containerKeywordProvider).isEmpty
          ? '还没有任何容器'
          : '没有匹配的容器',
      emptyIcon: Icons.inbox_outlined,
      onRefresh: () => ref.read(containersProvider.notifier).refresh(),
      onLoadMore: () => ref.read(containersProvider.notifier).loadMore(),
      onRetry: () => ref.invalidate(containersProvider),
      itemBuilder: (context, item, _) => ContainerTile(
        item: item,
        onTap: () => context.push('/containers/${item.id}'),
        onShowLogs: () => context.push('/containers/${item.id}/logs'),
        onAction: (action) => _handleAction(item, action),
      ),
    );
  }
}

/// 镜像 / 网络 / 存储卷 / 编排的快捷入口。
class _QuickNavBar extends StatelessWidget {
  const _QuickNavBar();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: [
          _NavChip(
            icon: Icons.album_outlined,
            label: '镜像',
            path: '/containers/image',
          ),
          _NavChip(
            icon: Icons.lan_outlined,
            label: '网络',
            path: '/containers/network',
          ),
          _NavChip(
            icon: Icons.storage_outlined,
            label: '存储卷',
            path: '/containers/volume',
          ),
          _NavChip(
            icon: Icons.dashboard_customize_outlined,
            label: '编排',
            path: '/containers/compose',
          ),
        ],
      ),
    );
  }
}

class _NavChip extends StatelessWidget {
  const _NavChip({required this.icon, required this.label, required this.path});

  final IconData icon;
  final String label;
  final String path;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        avatar: Icon(icon, size: 18),
        label: Text(label),
        onPressed: () => context.push(path),
      ),
    );
  }
}
