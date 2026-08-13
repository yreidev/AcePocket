import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/section_card.dart';
import '../models/process_info.dart';
import '../providers/process_providers.dart';
import 'formatters.dart';

/// 进程详情面板（`GET /api/process/detail`）。
Future<void> showProcessDetailSheet(
  BuildContext context, {
  required int pid,
  required String name,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, controller) => _ProcessDetailSheet(
        pid: pid,
        name: name,
        scrollController: controller,
      ),
    ),
  );
}

class _ProcessDetailSheet extends ConsumerWidget {
  const _ProcessDetailSheet({
    required this.pid,
    required this.name,
    required this.scrollController,
  });

  final int pid;
  final String name;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(processDetailProvider(pid));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: theme.textTheme.titleLarge),
                    Text(
                      'PID $pid',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              A11yIconButton(
                tooltip: '刷新进程详情',
                onPressed: () => ref.invalidate(processDetailProvider(pid)),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: async.when(
            loading: () => const LoadingView(message: '读取进程详情…'),
            error: (error, _) => ErrorView(
              error: error,
              onRetry: () => ref.invalidate(processDetailProvider(pid)),
            ),
            data: (process) => ListView(
              controller: scrollController,
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                SectionCard(
                  title: '基本信息',
                  child: _KeyValueList(
                    entries: [
                      ('PID', '${process.pid}'),
                      ('父进程 PID', '${process.ppid}'),
                      ('用户', process.username.isEmpty ? '-' : process.username),
                      ('状态', process.statusLabel),
                      ('后台进程', process.background ? '是' : '否'),
                      ('线程数', '${process.numThreads}'),
                      (
                        '启动时间',
                        process.startTime.isEmpty ? '-' : process.startTime,
                      ),
                    ],
                  ),
                ),
                SectionCard(
                  title: '资源占用',
                  child: _KeyValueList(
                    entries: [
                      ('CPU', formatCpuPercent(process.cpu)),
                      ('常驻内存 RSS', formatBytes(process.rss)),
                      ('虚拟内存 VMS', formatBytes(process.vms)),
                      ('内存峰值 HWM', formatBytes(process.hwm)),
                      ('数据段', formatBytes(process.data)),
                      ('栈', formatBytes(process.stack)),
                      ('锁定内存', formatBytes(process.locked)),
                      ('交换分区', formatBytes(process.swap)),
                      ('磁盘读取', formatBytes(process.diskRead)),
                      ('磁盘写入', formatBytes(process.diskWrite)),
                    ],
                  ),
                ),
                SectionCard(
                  title: '路径与命令行',
                  child: _KeyValueList(
                    entries: [
                      ('可执行文件', process.exe.isEmpty ? '-' : process.exe),
                      ('工作目录', process.cwd.isEmpty ? '-' : process.cwd),
                      ('命令行', process.cmdLine.isEmpty ? '-' : process.cmdLine),
                    ],
                    valueMaxLines: 6,
                  ),
                ),
                SectionCard(
                  title: '网络连接（${process.connections.length}）',
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: process.connections.isEmpty
                      ? _EmptyHint(text: '该进程没有网络连接')
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final conn in process.connections.take(50))
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _ConnectionRow(connection: conn),
                              ),
                            if (process.connections.length > 50)
                              _EmptyHint(
                                text:
                                    '仅显示前 50 条，共 ${process.connections.length} 条',
                              ),
                          ],
                        ),
                ),
                SectionCard(
                  title: '打开的文件（${process.openFiles.length}）',
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: process.openFiles.isEmpty
                      ? _EmptyHint(text: '无法读取或没有打开的文件')
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final file in process.openFiles.take(50))
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(
                                  'fd ${file.fd}  ${file.path}',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                            if (process.openFiles.length > 50)
                              _EmptyHint(
                                text:
                                    '仅显示前 50 条，共 ${process.openFiles.length} 条',
                              ),
                          ],
                        ),
                ),
                SectionCard(
                  title: '环境变量（${process.envs.length}）',
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: process.envs.isEmpty
                      ? _EmptyHint(text: '无法读取环境变量')
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final env in process.envs)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: SelectableText(
                                  env,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                          ],
                        ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _KeyValueList extends StatelessWidget {
  const _KeyValueList({required this.entries, this.valueMaxLines = 2});

  final List<(String, String)> entries;
  final int valueMaxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 100,
                  child: Text(
                    entry.$1,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.$2,
                    style: theme.textTheme.bodyMedium,
                    maxLines: valueMaxLines,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ConnectionRow extends StatelessWidget {
  const _ConnectionRow({required this.connection});

  final ProcessConnection connection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            connection.protocol,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSecondaryContainer,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${connection.localAddr} → '
            '${connection.remoteAddr.isEmpty ? '-' : connection.remoteAddr}'
            '${connection.status.isEmpty ? '' : '  ${connection.status}'}',
            style: theme.textTheme.bodySmall,
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
