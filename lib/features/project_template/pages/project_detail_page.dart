import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/format.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/section_card.dart';
import '../models/project.dart';
import '../providers/project_providers.dart';
import '../widgets/formatters.dart';

/// 项目详情页 `/projects/:id`。
///
/// 展示 systemd unit 的全部托管配置与实时运行状态，并提供启停 / 重启 /
/// 重载 / 自启 / 编辑 / 删除操作。
class ProjectDetailPage extends ConsumerStatefulWidget {
  const ProjectDetailPage({super.key, required this.projectId});

  final int projectId;

  @override
  ConsumerState<ProjectDetailPage> createState() => _ProjectDetailPageState();
}

class _ProjectDetailPageState extends ConsumerState<ProjectDetailPage> {
  bool _busy = false;

  Future<void> _refresh() async {
    ref.invalidate(projectDetailProvider(widget.projectId));
    await ref.read(projectDetailProvider(widget.projectId).future);
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) showSuccessSnack(context, success);
      ref.invalidate(projectDetailProvider(widget.projectId));
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearLog(ProjectDetail project) async {
    final ok = await showConfirmDialog(
      context,
      title: '清空服务日志',
      content: '将清空「${project.name}」的 systemd 服务日志，该操作不可恢复。',
      confirmText: '清空',
      danger: true,
    );
    if (!ok) return;
    await _run(
      () => ref.read(projectRepoProvider).clearLog(project.name),
      '已清空服务日志',
    );
  }

  Future<void> _stop(ProjectDetail project) async {
    final ok = await showConfirmDialog(
      context,
      title: '停止 ${project.name}',
      content: '停止后该项目对外提供的服务将不可用，确定停止吗？',
      confirmText: '停止',
      danger: true,
    );
    if (!ok) return;
    await _run(() => ref.read(projectRepoProvider).stop(project.name), '已停止');
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
    await _run(
      () => ref.read(projectRepoProvider).restart(project.name),
      '已重启',
    );
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
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(projectRepoProvider).delete(project.id);
      if (!mounted) return;
      showSuccessSnack(context, '已删除项目「${project.name}」');
      context.pop();
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(projectDetailProvider(widget.projectId));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          detailAsync.valueOrNull?.name ?? '项目详情',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (detailAsync.valueOrNull != null)
            PopupMenuButton<String>(
              tooltip: '更多操作',
              enabled: !_busy,
              onSelected: (value) {
                final project = detailAsync.valueOrNull;
                if (project == null) return;
                final repo = ref.read(projectRepoProvider);
                switch (value) {
                  case 'edit':
                    context.push('/projects/${project.id}/edit').then((_) {
                      if (mounted) _refresh();
                    });
                  case 'restart':
                    _restart(project);
                  case 'reload':
                    _run(() => repo.reload(project.name), '已重载配置');
                  case 'clear_log':
                    _clearLog(project);
                  case 'delete':
                    _delete(project);
                }
              },
              itemBuilder: (context) {
                final running = detailAsync.valueOrNull?.isRunning ?? false;
                return [
                  const PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.edit_outlined),
                      title: Text('编辑'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'restart',
                    enabled: running,
                    child: const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.restart_alt),
                      title: Text('重启'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'reload',
                    enabled: running,
                    child: const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.refresh),
                      title: Text('重载'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'clear_log',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.cleaning_services_outlined),
                      title: Text('清空服务日志'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.delete_outline,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      title: Text(
                        '删除',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                ];
              },
            ),
        ],
      ),
      body: detailAsync.when(
        loading: () => const LoadingView(message: '正在加载项目详情…'),
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () =>
              ref.invalidate(projectDetailProvider(widget.projectId)),
        ),
        data: (project) => RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: 8, bottom: 32),
            children: [
              _StatusCard(
                project: project,
                busy: _busy,
                onToggleStatus: () {
                  final repo = ref.read(projectRepoProvider);
                  if (project.isRunning) {
                    _stop(project);
                  } else {
                    _run(() => repo.start(project.name), '已启动');
                  }
                },
                onToggleAutostart: () {
                  final repo = ref.read(projectRepoProvider);
                  if (project.enabled) {
                    _run(() => repo.disable(project.name), '已关闭开机自启');
                  } else {
                    _run(() => repo.enable(project.name), '已开启开机自启');
                  }
                },
              ),
              SectionCard(
                title: '基本信息',
                child: _InfoList(
                  items: [
                    ('项目名称', project.name),
                    ('项目类型', projectTypeLabel(project.type)),
                    (
                      '描述',
                      project.description.isEmpty ? '—' : project.description,
                    ),
                    ('项目目录', project.rootDir.isEmpty ? '—' : project.rootDir),
                    (
                      '运行目录',
                      project.workingDir.isEmpty
                          ? '（同项目目录）'
                          : project.workingDir,
                    ),
                    ('运行用户', project.user.isEmpty ? '（默认 root）' : project.user),
                  ],
                ),
              ),
              SectionCard(
                title: '启动命令',
                child: _InfoList(
                  items: [
                    (
                      '启动前',
                      project.execStartPre.isEmpty ? '—' : project.execStartPre,
                    ),
                    ('启动', project.execStart.isEmpty ? '—' : project.execStart),
                    (
                      '启动后',
                      project.execStartPost.isEmpty
                          ? '—'
                          : project.execStartPost,
                    ),
                    ('停止', project.execStop.isEmpty ? '—' : project.execStop),
                    (
                      '重载',
                      project.execReload.isEmpty ? '—' : project.execReload,
                    ),
                  ],
                ),
              ),
              SectionCard(
                title: '重启策略',
                child: _InfoList(
                  items: [
                    ('策略', projectRestartLabel(project.restart)),
                    (
                      '重启间隔',
                      project.restartSec.isEmpty ? '—' : project.restartSec,
                    ),
                    (
                      '最大重启次数',
                      project.restartMax > 0 ? '${project.restartMax}' : '不限制',
                    ),
                    (
                      '启动超时',
                      project.timeoutStartSec > 0
                          ? '${project.timeoutStartSec} 秒'
                          : '默认',
                    ),
                    (
                      '停止超时',
                      project.timeoutStopSec > 0
                          ? '${project.timeoutStopSec} 秒'
                          : '默认',
                    ),
                  ],
                ),
              ),
              SectionCard(
                title: '环境变量',
                child: project.environments.isEmpty
                    ? const _EmptyHint(text: '未配置环境变量')
                    : _InfoList(
                        items: [
                          for (final env in project.environments)
                            (env.key, env.value.isEmpty ? '（空）' : env.value),
                        ],
                      ),
              ),
              SectionCard(
                title: '日志输出',
                child: _InfoList(
                  items: [
                    (
                      '标准输出',
                      project.standardOutput.isEmpty
                          ? '默认（journal）'
                          : project.standardOutput,
                    ),
                    (
                      '标准错误',
                      project.standardError.isEmpty
                          ? '默认（journal）'
                          : project.standardError,
                    ),
                  ],
                ),
              ),
              SectionCard(
                title: '依赖与启动顺序',
                child: _InfoList(
                  items: [
                    ('强依赖 Requires', _joinOrDash(project.requires)),
                    ('弱依赖 Wants', _joinOrDash(project.wants)),
                    ('在其之后启动 After', _joinOrDash(project.after)),
                    ('在其之前启动 Before', _joinOrDash(project.before)),
                  ],
                ),
              ),
              SectionCard(
                title: '资源限制',
                child: _InfoList(
                  items: [
                    (
                      '内存限制',
                      project.memoryLimit > 0
                          ? formatBytes(project.memoryLimit, fractionDigits: 1)
                          : '不限制',
                    ),
                    ('CPU 限制', _cpuQuotaLabel(project.cpuQuota)),
                  ],
                ),
              ),
              SectionCard(
                title: '安全加固',
                child: _InfoList(
                  items: [
                    (
                      '禁止提权 NoNewPrivileges',
                      project.noNewPrivileges ? '是' : '否',
                    ),
                    ('保护临时目录 ProtectTmp', project.protectTmp ? '是' : '否'),
                    ('保护主目录 ProtectHome', project.protectHome ? '是' : '否'),
                    (
                      '保护系统 ProtectSystem',
                      project.protectSystem.isEmpty
                          ? '关闭'
                          : project.protectSystem,
                    ),
                    ('可读写路径', _joinOrDash(project.readWritePaths)),
                    ('只读路径', _joinOrDash(project.readOnlyPaths)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _joinOrDash(List<String> values) =>
    values.isEmpty ? '—' : values.join('\n');

/// CPUQuota 展示：systemd 允许超过 100%（200% 表示 2 个核心），
/// 因此不能用 core 的 formatPercent（会钳制到 100%）。
String _cpuQuotaLabel(double quota) {
  if (quota <= 0) return '不限制';
  final cores = trimDouble(quota / 100);
  return '${formatCpuPercent(quota)}（约 $cores 个 CPU 核心）';
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.project,
    required this.busy,
    required this.onToggleStatus,
    required this.onToggleAutostart,
  });

  final ProjectDetail project;
  final bool busy;
  final VoidCallback onToggleStatus;
  final VoidCallback onToggleAutostart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final status = projectStatusOf(project.status);
    final (Color color, Color background) = switch (status) {
      ProjectStatus.active => (
        colorScheme.primary,
        colorScheme.primaryContainer,
      ),
      ProjectStatus.activating || ProjectStatus.deactivating => (
        colorScheme.tertiary,
        colorScheme.tertiaryContainer,
      ),
      ProjectStatus.failed => (colorScheme.error, colorScheme.errorContainer),
      ProjectStatus.inactive || ProjectStatus.unknown => (
        colorScheme.onSurfaceVariant,
        colorScheme.surfaceContainerHighest,
      ),
    };

    return SectionCard(
      title: '运行状态',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  projectStatusLabel(project.status),
                  style: theme.textTheme.labelMedium?.copyWith(color: color),
                ),
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: busy ? null : onToggleStatus,
                icon: Icon(
                  project.isRunning
                      ? Icons.stop_circle_outlined
                      : Icons.play_arrow,
                  size: 18,
                ),
                label: Text(project.isRunning ? '停止' : '启动'),
              ),
            ],
          ),
          if (project.isRunning) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                _Metric(label: 'PID', value: '${project.pid}'),
                _Metric(
                  label: '内存',
                  value: formatBytes(project.memory, fractionDigits: 1),
                ),
                _Metric(label: 'CPU', value: formatCpuPercent(project.cpu)),
                if (project.uptime.isNotEmpty)
                  _Metric(label: '运行时长', value: project.uptime),
              ],
            ),
          ],
          const SizedBox(height: 4),
          a11ySwitch(
            label: '项目 ${project.name} 的开机自启',
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('开机自启'),
              subtitle: const Text('对应 systemctl enable / disable'),
              value: project.enabled,
              onChanged: busy ? null : (_) => onToggleAutostart(),
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(value, style: theme.textTheme.titleSmall),
      ],
    );
  }
}

class _InfoList extends StatelessWidget {
  const _InfoList({required this.items});

  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 132,
                  child: Text(
                    item.$1,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: SelectableText(
                    item.$2,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.outline,
      ),
    );
  }
}
