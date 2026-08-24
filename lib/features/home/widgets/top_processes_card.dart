import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/section_card.dart';
import '../models/panel_models.dart';
import '../providers/home_providers.dart';
import 'formatters.dart';
import 'info_row.dart';

/// 占用最高的进程（CPU / 内存 / 磁盘 IO 三类，接口 `/home/top_processes`）。
class TopProcessesCard extends ConsumerStatefulWidget {
  const TopProcessesCard({super.key});

  @override
  ConsumerState<TopProcessesCard> createState() => _TopProcessesCardState();
}

class _TopProcessesCardState extends ConsumerState<TopProcessesCard> {
  static const _types = <String, String>{
    'cpu': 'CPU',
    'memory': '内存',
    'disk_io': '磁盘 IO',
  };

  String _type = 'cpu';

  String _formatValue(ProcessStat process) {
    switch (_type) {
      case 'memory':
        // 服务端 value 为进程 RSS 字节数（pkg/tools/tools.go CollectTopProcesses）。
        return formatBytes(process.value, fractionDigits: 1);
      case 'disk_io':
        return '读 ${formatBytes(process.read, fractionDigits: 1)} / '
            '写 ${formatBytes(process.write, fractionDigits: 1)}';
      case 'cpu':
      default:
        return formatPercent(process.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(topProcessesProvider(_type));

    return SectionCard(
      title: '进程占用 Top 5',
      trailing: A11yIconButton(
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.refresh, size: 18),
        tooltip: '刷新进程占用列表',
        onPressed: () => ref.invalidate(topProcessesProvider(_type)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              segments: [
                for (final entry in _types.entries)
                  ButtonSegment<String>(
                    value: entry.key,
                    label: Text(entry.value),
                  ),
              ],
              selected: {_type},
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onSelectionChanged: (selection) {
                setState(() => _type = selection.first);
              },
            ),
          ),
          const SizedBox(height: 10),
          async.when(
            loading: () => const SizedBox(
              height: 96,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (error, _) => InlineError(
              message: describeError(error),
              onRetry: () => ref.invalidate(topProcessesProvider(_type)),
            ),
            data: (processes) {
              if (processes.isEmpty) {
                return Text(
                  '暂无进程数据',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                );
              }
              return Column(
                children: [
                  for (final process in processes)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  process.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall,
                                ),
                                Text(
                                  'PID ${process.pid}'
                                  '${process.username.isEmpty ? '' : ' · ${process.username}'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // 「磁盘 IO」档位的文案是「读 X / 写 Y」，比另外两档
                          // 长得多，定宽 Text 在窄屏上会把左侧进程名挤到溢出。
                          Expanded(
                            flex: 2,
                            child: Align(
                              alignment: Alignment.topRight,
                              child: Text(
                                _formatValue(process),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: kTabularFigures,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
