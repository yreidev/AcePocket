import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/section_card.dart';
import '../models/task_item.dart';
import '../providers/tasks_providers.dart';
import '../widgets/format_utils.dart';
import '../widgets/setting_fields.dart';
import '../widgets/task_tile.dart';

/// 任务详情与日志。
///
/// 任务的 `log` 字段是日志文件路径，日志内容通过 `GET /api/file/tail` 读取。
class TaskDetailPage extends ConsumerStatefulWidget {
  const TaskDetailPage({super.key, required this.taskId});

  final int taskId;

  @override
  ConsumerState<TaskDetailPage> createState() => _TaskDetailPageState();
}

class _TaskDetailPageState extends ConsumerState<TaskDetailPage> {
  bool _busy = false;

  void _ok(String message) {
    if (!mounted) return;
    showSuccessSnack(context, message);
  }

  void _fail(Object error) {
    if (!mounted) return;
    showErrorSnack(context, error);
  }

  void _refresh(TaskItem? task) {
    ref.invalidate(taskDetailProvider(widget.taskId));
    if (task != null && task.log.isNotEmpty) {
      ref.invalidate(taskLogProvider(task.log));
    }
  }

  Future<void> _cancel(TaskItem task) async {
    if (_busy) return;
    final ok = await showConfirmDialog(
      context,
      title: '取消任务',
      content: '确定要取消任务「${task.name.isEmpty ? '#${task.id}' : task.name}」吗？'
          '\n面板会尝试终止正在执行的操作，可能导致该操作处于中间状态。',
      confirmText: '取消任务',
      cancelText: '继续执行',
      danger: true,
    );
    if (!ok || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(taskRepoProvider).cancel(task.id);
      _refresh(task);
      ref.invalidate(taskListProvider);
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
      ref.invalidate(taskListProvider);
      if (!mounted) return;
      _ok('任务记录已删除');
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/tasks');
      }
    } catch (e) {
      _fail(e);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearLog(TaskItem task) async {
    if (_busy || task.log.isEmpty) return;
    final ok = await showConfirmDialog(
      context,
      title: '清空日志',
      content: '确定要清空日志文件 ${task.log} 吗？该操作不可撤销。',
      confirmText: '清空日志',
      danger: true,
    );
    if (!ok || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(taskRepoProvider).truncateLog(task.log);
      ref.invalidate(taskLogProvider(task.log));
      _ok('日志已清空');
    } catch (e) {
      _fail(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final taskAsync = ref.watch(taskDetailProvider(widget.taskId));

    return Scaffold(
      appBar: AppBar(
        title: Text('任务 #${widget.taskId}'),
        actions: [
          A11yIconButton(
            tooltip: '刷新任务详情',
            icon: const Icon(Icons.refresh),
            onPressed: () => _refresh(taskAsync.valueOrNull),
          ),
        ],
      ),
      body: taskAsync.when(
        loading: () => const LoadingView(message: '正在加载任务详情…'),
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(taskDetailProvider(widget.taskId)),
        ),
        data: (task) => Column(
          children: [
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => _refresh(task),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 32),
                  children: [
                    SectionCard(
                      title: '任务信息',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  task.name.isEmpty
                                      ? '任务 #${task.id}'
                                      : task.name,
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                              const SizedBox(width: 8),
                              TaskStatusChip(
                                status: task.status,
                                label: task.statusLabel,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          InfoRow(label: '任务 ID', value: '${task.id}'),
                          InfoRow(
                            label: '创建时间',
                            value: formatDateTime(task.createdAt),
                          ),
                          InfoRow(
                            label: '更新时间',
                            value: formatDateTime(task.updatedAt),
                          ),
                          InfoRow(
                            label: '日志文件',
                            value: task.log.isEmpty ? '无' : task.log,
                            copyable: task.log.isNotEmpty,
                          ),
                        ],
                      ),
                    ),
                    _TaskLogCard(
                      task: task,
                      busy: _busy,
                      onClear: () => _clearLog(task),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Row(
                        children: [
                          if (task.isActive)
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed: _busy ? null : () => _cancel(task),
                                icon: const Icon(Icons.stop_circle_outlined),
                                label: const Text('取消任务'),
                              ),
                            )
                          else
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _busy ? null : () => _delete(task),
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('删除任务记录'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor:
                                      Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 任务日志卡片。
class _TaskLogCard extends ConsumerWidget {
  const _TaskLogCard({
    required this.task,
    required this.busy,
    required this.onClear,
  });

  final TaskItem task;
  final bool busy;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    if (task.log.isEmpty) {
      return const SectionCard(
        title: '任务日志',
        child: Text('该任务没有关联日志文件'),
      );
    }

    final logAsync = ref.watch(taskLogProvider(task.log));

    return SectionCard(
      title: '任务日志',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          A11yIconButton(
            tooltip: '复制任务日志',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.copy_outlined, size: 18),
            onPressed: logAsync.valueOrNull == null
                ? null
                : () async {
                    await Clipboard.setData(
                      ClipboardData(text: logAsync.value!.text),
                    );
                    if (!context.mounted) return;
                    showSuccessSnack(context, '日志已复制到剪贴板');
                  },
          ),
          A11yIconButton(
            tooltip: '刷新任务日志',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: () => ref.invalidate(taskLogProvider(task.log)),
          ),
          A11yIconButton(
            tooltip: '清空任务日志',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.delete_sweep_outlined,
              size: 18,
              color: theme.colorScheme.error,
            ),
            onPressed: busy ? null : onClear,
          ),
        ],
      ),
      child: logAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        error: (error, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              describeError(error),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => ref.invalidate(taskLogProvider(task.log)),
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ),
          ],
        ),
        data: (result) {
          if (result.lines.isEmpty) {
            return Text(
              '日志为空',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '最近 ${result.lines.length} 行'
                '${result.hasMore ? '（更早的内容已省略）' : ''}'
                ' · 文件大小 ${formatBytes(result.size)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 420),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Scrollbar(
                  child: SingleChildScrollView(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SelectableText(
                        result.text,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
