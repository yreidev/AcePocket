import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../models/task_item.dart';
import '../providers/tasks_providers.dart';
import '../widgets/list_footer.dart';
import '../widgets/task_tile.dart';

/// 任务中心（`/api/task`）：异步任务列表、取消与删除。
class TasksPage extends ConsumerStatefulWidget {
  const TasksPage({super.key});

  @override
  ConsumerState<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends ConsumerState<TasksPage> {
  final ScrollController _scrollController = ScrollController();
  bool _busy = false;

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
      ref.read(taskListProvider.notifier).loadMore();
    }
  }

  void _ok(String message) {
    if (!mounted) return;
    showSuccessSnack(context, message);
  }

  void _fail(Object error) {
    if (!mounted) return;
    showErrorSnack(context, error);
  }

  Future<void> _refreshAll() async {
    ref.invalidate(taskRunningProvider);
    await ref.read(taskListProvider.notifier).refresh();
  }

  Future<void> _cancel(TaskItem task) async {
    if (_busy) return;
    final ok = await showConfirmDialog(
      context,
      title: '取消任务',
      content:
          '确定要取消任务「${task.name.isEmpty ? '#${task.id}' : task.name}」吗？'
          '\n面板会尝试终止正在执行的操作，可能导致该操作处于中间状态。',
      confirmText: '取消任务',
      cancelText: '继续执行',
      danger: true,
    );
    if (!ok || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(taskRepoProvider).cancel(task.id);
      await _refreshAll();
      _ok('已发送取消请求');
    } catch (e) {
      _fail(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(TaskItem task) async {
    if (_busy) return;
    final ok = await showConfirmDialog(
      context,
      title: '删除任务',
      content: '确定要删除任务「${task.name.isEmpty ? '#${task.id}' : task.name}」的记录吗？',
      confirmText: '删除记录',
      danger: true,
    );
    if (!ok || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(taskRepoProvider).delete(task.id);
      await _refreshAll();
      _ok('任务记录已删除');
    } catch (e) {
      _fail(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final listAsync = ref.watch(taskListProvider);
    final runningAsync = ref.watch(taskRunningProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('任务中心'),
        actions: [
          A11yIconButton(
            tooltip: '刷新任务列表',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(taskRunningProvider);
              ref.invalidate(taskListProvider);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          if (runningAsync.valueOrNull == true)
            Container(
              width: double.infinity,
              color: theme.colorScheme.primaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '有任务正在执行中，下拉可刷新进度',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: listAsync.when(
              loading: () => const LoadingView(message: '正在加载任务列表…'),
              error: (error, _) => ErrorView(
                error: error,
                onRetry: () => ref.invalidate(taskListProvider),
              ),
              data: (state) {
                if (state.items.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: _refreshAll,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.sizeOf(context).height * 0.6,
                          child: const EmptyView(
                            message: '暂无后台任务',
                            icon: Icons.task_alt_outlined,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    try {
                      await _refreshAll();
                    } catch (e) {
                      _fail(e);
                    }
                  },
                  child: ListView.builder(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(top: 4, bottom: 24),
                    itemCount: state.items.length + 1,
                    itemBuilder: (context, index) {
                      if (index == state.items.length) {
                        return ListFooter(
                          loading: state.loadingMore,
                          hasMore: state.hasMore,
                          total: state.total,
                        );
                      }
                      final task = state.items[index];
                      return TaskTile(
                        task: task,
                        onTap: () => context.push('/tasks/${task.id}'),
                        onCancel: () => _cancel(task),
                        onDelete: () => _delete(task),
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
