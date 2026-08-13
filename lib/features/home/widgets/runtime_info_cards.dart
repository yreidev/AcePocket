import 'package:flutter/material.dart';

import '../../../core/widgets/section_card.dart';
import '../models/runtime_models.dart';
import 'formatters.dart';
import 'info_row.dart';

/// 运行时信息卡片组（概览 / 内存 / 堆 / 运行时开销 / GC）。
class RuntimeInfoCards extends StatelessWidget {
  const RuntimeInfoCards({super.key, required this.info});

  final RuntimeInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: '概览',
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: MetricTile(
                      label: '协程数',
                      value: '${info.goroutines}',
                      icon: Icons.alt_route_rounded,
                    ),
                  ),
                  Expanded(
                    child: MetricTile(
                      label: '逻辑 CPU',
                      value: '${info.numCpu}',
                      icon: Icons.memory_rounded,
                    ),
                  ),
                  Expanded(
                    child: MetricTile(
                      label: '占用内存',
                      value: formatBytes(info.memoryAlloc),
                      icon: Icons.donut_small_rounded,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              InfoRow(label: 'Go 版本', value: info.goVersion, monospace: true),
              InfoRow(
                label: '面板运行时长',
                value: formatUptime(info.uptime.round()),
              ),
              InfoRow(label: 'cgo 调用', value: '${info.numCgoCall}'),
            ],
          ),
        ),
        SectionCard(
          title: '内存',
          child: Column(
            children: [
              InfoRow(label: '正在使用', value: formatBytes(info.memoryAlloc)),
              InfoRow(label: '累计分配', value: formatBytes(info.memoryTotal)),
              InfoRow(label: '向系统申请', value: formatBytes(info.memorySys)),
              InfoRow(label: '分配次数', value: '${info.memoryMallocs}'),
              InfoRow(label: '释放次数', value: '${info.memoryFrees}'),
              InfoRow(label: '存活对象', value: '${info.liveObjects}'),
              InfoRow(label: '指针查找', value: '${info.memoryLookups}'),
            ],
          ),
        ),
        SectionCard(
          title: '堆',
          child: Column(
            children: [
              InfoRow(label: '已分配', value: formatBytes(info.heapAlloc)),
              InfoRow(label: '系统预留', value: formatBytes(info.heapSys)),
              InfoRow(label: '使用中', value: formatBytes(info.heapInuse)),
              InfoRow(label: '空闲', value: formatBytes(info.heapIdle)),
              InfoRow(label: '已归还系统', value: formatBytes(info.heapReleased)),
              InfoRow(label: '堆对象数', value: '${info.heapObjects}'),
            ],
          ),
        ),
        SectionCard(
          title: '运行时开销',
          child: Column(
            children: [
              InfoRow(label: '栈使用中', value: formatBytes(info.stackInuse)),
              InfoRow(label: '栈系统预留', value: formatBytes(info.stackSys)),
              InfoRow(label: 'MSpan 使用', value: formatBytes(info.mspanInuse)),
              InfoRow(label: 'MSpan 预留', value: formatBytes(info.mspanSys)),
              InfoRow(label: 'MCache 使用', value: formatBytes(info.mcacheInuse)),
              InfoRow(label: 'MCache 预留', value: formatBytes(info.mcacheSys)),
              InfoRow(label: '性能剖析桶', value: formatBytes(info.buckHashSys)),
              InfoRow(label: 'GC 元数据', value: formatBytes(info.gcSys)),
              InfoRow(label: '其他', value: formatBytes(info.otherSys)),
            ],
          ),
        ),
        SectionCard(
          title: '垃圾回收',
          child: Column(
            children: [
              InfoRow(label: 'GC 次数', value: '${info.gcNum}'),
              InfoRow(label: '强制 GC', value: '${info.gcNumForced}'),
              InfoRow(label: '下次 GC 阈值', value: formatBytes(info.gcNext)),
              InfoRow(
                label: '上次 GC',
                value: info.lastGcTime == null
                    ? '尚未发生'
                    : formatDateTime(info.lastGcTime),
              ),
              InfoRow(
                label: '累计暂停',
                value: formatDurationNanos(info.gcPauseTotal),
              ),
              InfoRow(
                label: 'GC 占用 CPU',
                value: '${(info.gcCpuFraction * 100).toStringAsFixed(3)}%',
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text(
            '以上数据来自面板进程的 Go 运行时（runtime.MemStats），'
            '用于排查面板自身的内存与协程问题，与服务器整体负载无关。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// 纳秒时长转可读文本（GC 暂停统计用）。
String formatDurationNanos(int nanos) {
  if (nanos <= 0) return '0 ms';
  if (nanos < 1000) return '$nanos ns';
  final micros = nanos / 1000;
  if (micros < 1000) return '${micros.toStringAsFixed(2)} μs';
  final millis = micros / 1000;
  if (millis < 1000) return '${millis.toStringAsFixed(2)} ms';
  return '${(millis / 1000).toStringAsFixed(2)} s';
}
