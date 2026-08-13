import 'package:flutter/material.dart';

import '../models/process_info.dart';
import 'formatters.dart';

/// 进程列表项。
class ProcessTile extends StatelessWidget {
  const ProcessTile({
    super.key,
    required this.process,
    required this.onTap,
    required this.onKill,
    required this.onSignal,
    this.busy = false,
  });

  final ProcessInfo process;

  /// 查看详情。
  final VoidCallback onTap;

  /// 结束进程（SIGKILL）。
  final VoidCallback onKill;

  /// 发送信号。
  final VoidCallback onSignal;

  /// 是否有操作进行中。
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
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
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          child: Row(
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
                            process.name,
                            style: theme.textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _ProcessStatusChip(process: process),
                      ],
                    ),
                    const SizedBox(height: 6),
                    DefaultTextStyle(
                      style:
                          theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ) ??
                          const TextStyle(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _Metric(
                                icon: Icons.tag,
                                text: 'PID ${process.pid}',
                              ),
                              const SizedBox(width: 12),
                              _Metric(
                                icon: Icons.person_outline,
                                text: process.username.isEmpty
                                    ? '未知用户'
                                    : process.username,
                              ),
                              const SizedBox(width: 12),
                              _Metric(
                                icon: Icons.account_tree_outlined,
                                text: '${process.numThreads} 线程',
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              _Metric(
                                icon: Icons.speed,
                                text: 'CPU ${formatCpuPercent(process.cpu)}',
                              ),
                              const SizedBox(width: 12),
                              _Metric(
                                icon: Icons.memory,
                                text: formatBytes(process.rss),
                              ),
                              if (process.startTime.isNotEmpty) ...[
                                const SizedBox(width: 12),
                                Flexible(
                                  child: _Metric(
                                    icon: Icons.schedule,
                                    text: process.startTime,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.only(right: 12, top: 8),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                PopupMenuButton<String>(
                  tooltip: '进程 ${process.name} 的操作',
                  onSelected: (value) {
                    switch (value) {
                      case 'detail':
                        onTap();
                        break;
                      case 'kill':
                        onKill();
                        break;
                      case 'signal':
                        onSignal();
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'detail',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.info_outline),
                        title: Text('查看详情'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'signal',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.bolt_outlined),
                        title: Text('发送信号'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'kill',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.dangerous_outlined,
                          color: colorScheme.error,
                        ),
                        title: Text(
                          '结束进程',
                          style: TextStyle(color: colorScheme.error),
                        ),
                      ),
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

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = DefaultTextStyle.of(context).style.color;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Flexible(
          child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

class _ProcessStatusChip extends StatelessWidget {
  const _ProcessStatusChip({required this.process});

  final ProcessInfo process;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    late final Color background;
    late final Color foreground;
    switch (process.status) {
      case 'running':
        background = colorScheme.tertiaryContainer;
        foreground = colorScheme.onTertiaryContainer;
        break;
      case 'zombie':
      case 'blocked':
      case 'stop':
        background = colorScheme.errorContainer;
        foreground = colorScheme.onErrorContainer;
        break;
      default:
        background = colorScheme.surfaceContainerHighest;
        foreground = colorScheme.onSurfaceVariant;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        process.statusLabel,
        style: theme.textTheme.labelSmall?.copyWith(color: foreground),
      ),
    );
  }
}
