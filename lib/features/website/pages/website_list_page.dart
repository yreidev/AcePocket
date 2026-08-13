import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/storage/server_store.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../models/website.dart';
import '../providers/website_providers.dart';
import '../widgets/delete_website_dialog.dart';
import '../widgets/website_list_tile.dart';

/// 网站列表页 `/websites`。
///
/// 同时由外壳的底部导航作为「网站」tab 使用，因此自带 Scaffold 与 AppBar。
class WebsiteListPage extends ConsumerStatefulWidget {
  const WebsiteListPage({super.key});

  @override
  ConsumerState<WebsiteListPage> createState() => _WebsiteListPageState();
}

class _WebsiteListPageState extends ConsumerState<WebsiteListPage> {
  final ScrollController _scrollController = ScrollController();

  /// 正在执行操作的网站 id（该行禁用交互）。
  int? _busyId;

  static const _typeFilters = <({String value, String label})>[
    (value: 'all', label: '全部'),
    (value: 'proxy', label: '反向代理'),
    (value: 'php', label: 'PHP'),
    (value: 'static', label: '纯静态'),
  ];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 240) {
      ref.read(websiteListProvider.notifier).loadMore();
    }
  }

  Future<void> _refresh() => ref.read(websiteListProvider.notifier).refresh();

  /// 操作完成后静默刷新列表（失败仅提示，不打断当前界面）。
  Future<void> _reloadQuietly() async {
    try {
      await ref.read(websiteListProvider.notifier).reload();
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _runBusy(int id, Future<void> Function() action) async {
    setState(() => _busyId = id);
    try {
      await action();
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _toggleStatus(Website website, bool status) async {
    // 停用会让线上站点立刻返回停止页，误触代价高（列表里的开关很容易被划到），
    // 因此只对「停用」方向做二次确认；启用无破坏性，保持一步到位。
    if (!status) {
      final ok = await showConfirmDialog(
        context,
        title: '停用网站',
        content: '停用后访问「${website.name}」将返回停止页，直到重新启用。确定停用吗？',
        confirmText: '停用',
        danger: true,
      );
      if (!ok || !mounted) return;
    }
    await _runBusy(website.id, () async {
      await ref.read(websiteRepoProvider).updateStatus(website.id, status);
      if (mounted) {
        showSuccessSnack(context, status ? '已启用网站' : '已停用网站');
      }
      await _reloadQuietly();
    });
  }

  Future<void> _delete(Website website) async {
    final options =
        await showDeleteWebsiteDialog(context, websiteName: website.name);
    if (options == null) return;
    await _runBusy(website.id, () async {
      await ref.read(websiteRepoProvider).delete(
            website.id,
            deletePath: options.deletePath,
            deleteDb: options.deleteDb,
          );
      if (mounted) showSuccessSnack(context, '已删除网站 ${website.name}');
      ref.read(websiteListProvider.notifier).removeItem(website.id);
      await _reloadQuietly();
    });
  }

  Future<void> _openDetail(Website website) async {
    await context.push('/websites/${website.id}');
    await _reloadQuietly();
  }

  void _openStats(Website website) {
    context.push('/websites/${website.id}/stats', extra: website.name);
  }

  Future<void> _openCreate() async {
    await context.push('/websites/create');
    await _reloadQuietly();
  }

  @override
  Widget build(BuildContext context) {
    final server = ref.watch(activeServerProvider);
    if (server == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('网站')),
        body: EmptyView(
          message: '还没有配置任何服务器\n添加后即可管理网站',
          icon: Icons.dns_outlined,
          action: FilledButton.icon(
            onPressed: () => context.go('/servers/setup'),
            icon: const Icon(Icons.add),
            label: const Text('添加服务器'),
          ),
        ),
      );
    }

    final type = ref.watch(websiteTypeFilterProvider);
    final listState = ref.watch(websiteListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('网站'),
        actions: [
          A11yIconButton(
            tooltip: '刷新网站列表',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            tooltip: '网站列表的更多操作',
            onSelected: (value) async {
              switch (value) {
                case 'settings':
                  await context.push('/websites/settings');
                  // 默认站点可能变化，返回后静默刷新列表。
                  await _reloadQuietly();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.tune),
                  title: Text('默认设置'),
                ),
              ),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final filter in _typeFilters)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Center(
                      child: ChoiceChip(
                        label: Text(filter.label),
                        selected: type == filter.value,
                        onSelected: (_) {
                          if (type == filter.value) return;
                          ref.read(websiteTypeFilterProvider.notifier).state =
                              filter.value;
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        icon: const Icon(Icons.add),
        label: const Text('新建网站'),
      ),
      body: listState.when(
        loading: () => const LoadingView(message: '正在加载网站…'),
        error: (error, _) => ErrorView(error: error, onRetry: _refresh),
        data: (state) {
          if (state.items.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                  EmptyView(
                    message: type == 'all' ? '还没有创建任何网站' : '当前类型下没有网站',
                    icon: Icons.language_outlined,
                    action: FilledButton.icon(
                      onPressed: _openCreate,
                      icon: const Icon(Icons.add),
                      label: const Text('新建网站'),
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 4, bottom: 96),
              itemCount: state.items.length + 1,
              itemBuilder: (context, index) {
                if (index == state.items.length) {
                  return _ListFooter(
                    hasMore: state.hasMore,
                    loadingMore: state.loadingMore,
                    error: state.loadMoreError,
                    count: state.items.length,
                    onRetry: () =>
                        ref.read(websiteListProvider.notifier).loadMore(),
                  );
                }
                final website = state.items[index];
                return WebsiteListTile(
                  website: website,
                  busy: _busyId == website.id,
                  onTap: () => _openDetail(website),
                  onToggleStatus: (value) => _toggleStatus(website, value),
                  onStats: () => _openStats(website),
                  onDelete: () => _delete(website),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _ListFooter extends StatelessWidget {
  const _ListFooter({
    required this.hasMore,
    required this.loadingMore,
    required this.error,
    required this.count,
    required this.onRetry,
  });

  final bool hasMore;
  final bool loadingMore;
  final Object? error;
  final int count;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Text(
              '加载更多失败：${describeError(error!)}',
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重新加载'),
            ),
          ],
        ),
      );
    }
    if (loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Text(
          hasMore ? '上拉加载更多' : '共 $count 个网站',
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
