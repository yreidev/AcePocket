import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/version/panel_feature.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/feature_gate.dart';
import '../../../core/widgets/loading_view.dart';
import '../models/project.dart';
import '../providers/project_providers.dart';
import '../widgets/list_footer.dart';
import '../widgets/project_tile.dart';

/// 项目列表页 `/projects`。
///
/// 项目即面板托管的 systemd 服务，支持按类型筛选、启停、自启、编辑与删除。
class ProjectListPage extends ConsumerStatefulWidget {
  const ProjectListPage({super.key});

  @override
  ConsumerState<ProjectListPage> createState() => _ProjectListPageState();
}

class _ProjectListPageState extends ConsumerState<ProjectListPage> {
  final ScrollController _scrollController = ScrollController();

  /// 正在执行操作的项目 id（禁用该行交互）。
  int? _busyId;

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
      _loadMore();
    }
  }

  /// 加载下一页；失败会记录到 `state.loadMoreError`，由列表底部展示并可重试。
  Future<void> _loadMore() => ref.read(projectListProvider.notifier).loadMore();

  Future<void> _refresh() => ref.read(projectListProvider.notifier).refresh();

  /// 增删改之后静默刷新列表（保留旧数据，失败仅提示）。
  Future<void> _reloadQuietly() async {
    try {
      await ref.read(projectListProvider.notifier).reload();
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

  Future<void> _toggleStatus(ProjectDetail project) async {
    if (project.isRunning) {
      final ok = await showConfirmDialog(
        context,
        title: '停止 ${project.name}',
        content: '停止后该项目对外提供的服务将不可用，确定停止吗？',
        confirmText: '停止',
        danger: true,
      );
      if (!ok) return;
    }
    await _runBusy(project.id, () async {
      final repo = ref.read(projectRepoProvider);
      if (project.isRunning) {
        await repo.stop(project.name);
      } else {
        await repo.start(project.name);
      }
      if (mounted) {
        showSuccessSnack(context, project.isRunning ? '已停止' : '已启动');
      }
      await _reloadQuietly();
    });
  }

  Future<void> _restart(ProjectDetail project) async {
    // 重启会中断正在处理的请求，与「停止」同样需要二次确认。
    final ok = await showConfirmDialog(
      context,
      title: '重启 ${project.name}',
      content: '重启期间该项目会短暂不可用，确定重启吗？',
      confirmText: '重启',
      danger: true,
    );
    if (!ok) return;
    await _runBusy(project.id, () async {
      await ref.read(projectRepoProvider).restart(project.name);
      if (mounted) showSuccessSnack(context, '已重启');
      await _reloadQuietly();
    });
  }

  Future<void> _reload(ProjectDetail project) async {
    await _runBusy(project.id, () async {
      await ref.read(projectRepoProvider).reload(project.name);
      if (mounted) showSuccessSnack(context, '已重载配置');
      await _reloadQuietly();
    });
  }

  Future<void> _toggleAutostart(ProjectDetail project) async {
    await _runBusy(project.id, () async {
      final repo = ref.read(projectRepoProvider);
      if (project.enabled) {
        await repo.disable(project.name);
      } else {
        await repo.enable(project.name);
      }
      ref
          .read(projectListProvider.notifier)
          .replaceWhere(
            (item) => item.id == project.id,
            (item) => item.copyWith(enabled: !project.enabled),
          );
      if (mounted) {
        showSuccessSnack(context, project.enabled ? '已关闭开机自启' : '已开启开机自启');
      }
    });
  }

  Future<void> _delete(ProjectDetail project) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除项目',
      content:
          '确定要删除项目「${project.name}」吗？\n'
          '面板会同时删除对应的 systemd 服务配置，项目目录中的文件不会被移除。',
      confirmText: '删除',
      danger: true,
    );
    if (!ok) return;
    await _runBusy(project.id, () async {
      await ref.read(projectRepoProvider).delete(project.id);
      if (mounted) showSuccessSnack(context, '已删除项目「${project.name}」');
      await _reloadQuietly();
    });
  }

  Future<void> _openDetail(ProjectDetail project) async {
    await context.push('/projects/${project.id}');
    await _reloadQuietly();
  }

  Future<void> _openEdit(ProjectDetail project) async {
    await context.push('/projects/${project.id}/edit');
    await _reloadQuietly();
  }

  Future<void> _openCreate() async {
    await context.push('/projects/create');
    await _reloadQuietly();
  }

  @override
  Widget build(BuildContext context) {
    final listState = ref.watch(projectListProvider);
    final type = ref.watch(projectTypeFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('项目'),
        actions: [
          A11yIconButton(
            tooltip: '打开应用模板市场',
            onPressed: () => context.push('/templates'),
            icon: const Icon(Icons.widgets_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        icon: const Icon(Icons.add),
        label: const Text('新建项目'),
      ),
      body: Column(
        children: [
          const FeatureUnsupportedBanner(feature: PanelFeature.project),
          _TypeFilterBar(
            selected: type,
            onSelected: (value) =>
                ref.read(projectTypeFilterProvider.notifier).select(value),
          ),
          const Divider(height: 1),
          Expanded(
            child: listState.when(
              loading: () => const LoadingView(message: '正在加载项目…'),
              error: (error, _) => ErrorView(error: error, onRetry: _refresh),
              data: (state) {
                if (state.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.15,
                        ),
                        EmptyView(
                          message: type == 'all'
                              ? '还没有项目\n可以新建项目，由面板生成 systemd 服务托管你的程序'
                              : '当前分类下没有项目',
                          icon: Icons.rocket_launch_outlined,
                          action: FilledButton.icon(
                            onPressed: _openCreate,
                            icon: const Icon(Icons.add),
                            label: const Text('新建项目'),
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
                        return ListFooter(
                          loading: state.loadingMore,
                          hasMore: state.hasMore,
                          total: state.total,
                          unit: '个项目',
                          error: state.loadMoreError,
                          onRetry: _loadMore,
                        );
                      }
                      final project = state.items[index];
                      return ProjectTile(
                        project: project,
                        busy: _busyId == project.id,
                        onTap: () => _openDetail(project),
                        onToggleStatus: () => _toggleStatus(project),
                        onRestart: () => _restart(project),
                        onReload: () => _reload(project),
                        onToggleAutostart: () => _toggleAutostart(project),
                        onEdit: () => _openEdit(project),
                        onDelete: () => _delete(project),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 项目类型筛选栏（全部 + 各语言类型）。
class _TypeFilterBar extends StatelessWidget {
  const _TypeFilterBar({required this.selected, required this.onSelected});

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final options = <(String, String)>[('all', '全部'), ...kProjectTypeOptions];
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final option = options[index];
          return ChoiceChip(
            label: Text(option.$2),
            selected: selected == option.$1,
            onSelected: (_) => onSelected(option.$1),
          );
        },
      ),
    );
  }
}
