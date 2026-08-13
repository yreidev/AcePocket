import 'package:flutter/material.dart';

import '../../../core/utils/format.dart';
import '../../../core/widgets/a11y.dart';
import '../models/project.dart';
import 'formatters.dart';

/// 项目列表项卡片：状态、类型、路径、资源占用 + 常用操作。
class ProjectTile extends StatelessWidget {
  const ProjectTile({
    super.key,
    required this.project,
    required this.onTap,
    required this.onToggleStatus,
    required this.onRestart,
    required this.onReload,
    required this.onToggleAutostart,
    required this.onEdit,
    required this.onDelete,
    this.busy = false,
  });

  final ProjectDetail project;
  final VoidCallback onTap;
  final VoidCallback onToggleStatus;
  final VoidCallback onRestart;
  final VoidCallback onReload;
  final VoidCallback onToggleAutostart;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// 该条目正在执行操作（禁用交互）。
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final status = projectStatusOf(project.status);

    final (Color statusColor, Color statusBg) = switch (status) {
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

    final running = project.isRunning;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                                project.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _Chip(
                              text: projectTypeLabel(project.type),
                              color: colorScheme.secondary,
                              background: colorScheme.secondaryContainer,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          project.description.isEmpty
                              ? '暂无描述'
                              : project.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(right: 6, top: 2),
                    child: _Chip(
                      text: projectStatusLabel(project.status),
                      color: statusColor,
                      background: statusBg,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _InfoRow(
                icon: Icons.folder_outlined,
                text: project.rootDir.isEmpty ? '未设置目录' : project.rootDir,
              ),
              if (project.execStart.isNotEmpty)
                _InfoRow(
                  icon: Icons.play_circle_outline,
                  text: project.execStart,
                ),
              if (running) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    _Metric(label: 'PID', value: '${project.pid}'),
                    _Metric(
                      label: '内存',
                      value: formatBytes(project.memory, fractionDigits: 1),
                    ),
                    _Metric(label: 'CPU', value: formatCpuPercent(project.cpu)),
                    if (project.uptime.isNotEmpty)
                      _Metric(label: '运行', value: project.uptime),
                  ],
                ),
              ],
              const SizedBox(height: 2),
              Row(
                children: [
                  Expanded(
                    // 读屏播报「项目 xxx 的开机自启」+ 开关自身的开/关状态，
                    // 避免列表里一排匿名开关分不清控制的是哪个项目。
                    child: a11ySwitch(
                      label: '项目 ${project.name} 的开机自启',
                      child: Row(
                        children: [
                          Text(
                            '自启',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Switch(
                            value: project.enabled,
                            onChanged: busy ? null : (_) => onToggleAutostart(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: busy ? null : onToggleStatus,
                    icon: Icon(
                      running ? Icons.stop_circle_outlined : Icons.play_arrow,
                      size: 18,
                    ),
                    label: Text(running ? '停止' : '启动'),
                  ),
                  PopupMenuButton<String>(
                    tooltip: '更多操作',
                    enabled: !busy,
                    onSelected: (value) {
                      switch (value) {
                        case 'restart':
                          onRestart();
                        case 'reload':
                          onReload();
                        case 'edit':
                          onEdit();
                        case 'delete':
                          onDelete();
                      }
                    },
                    itemBuilder: (context) => [
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
                        value: 'edit',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.edit_outlined),
                          title: Text('编辑'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.delete_outline,
                            color: colorScheme.error,
                          ),
                          title: Text(
                            '删除',
                            style: TextStyle(color: colorScheme.error),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.text,
    required this.color,
    required this.background,
  });

  final String text;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: theme.colorScheme.outline),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
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
    return Text(
      '$label $value',
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
