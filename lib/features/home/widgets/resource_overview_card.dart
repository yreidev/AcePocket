import 'package:flutter/material.dart';

import '../../../core/widgets/section_card.dart';
import '../models/current_info.dart';
import '../providers/home_providers.dart';
import 'formatters.dart';
import 'mini_chart.dart';

/// 实时资源总览：CPU 与内存的环形仪表 + 迷你趋势图。
class ResourceOverviewCard extends StatelessWidget {
  const ResourceOverviewCard({super.key, required this.state, this.updatedAt});

  final RealtimeState state;

  /// 最近一次采样时间（展示在标题右侧）。
  final DateTime? updatedAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = state.info;
    final memPercent = info.mem.total > 0
        ? info.mem.used / info.mem.total * 100
        : info.mem.usedPercent;

    return SectionCard(
      title: '实时负载',
      trailing: updatedAt == null
          ? null
          : Text(
              '更新于 ${formatChartTimeOfDay(updatedAt!)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFeatures: kTabularFigures,
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _Gauge(
                  label: 'CPU',
                  percent: info.percent,
                  caption: info.cores > 0 ? '${info.cores} 核' : '—',
                  color: theme.colorScheme.primary,
                ),
              ),
              Expanded(
                child: _Gauge(
                  label: '内存',
                  percent: memPercent,
                  caption:
                      '${formatBytes(info.mem.used)} / ${formatBytes(info.mem.total)}',
                  color: theme.colorScheme.tertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Trend(
                  title: 'CPU 趋势',
                  values: state.cpuHistory,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Trend(
                  title: '内存趋势',
                  values: state.memHistory,
                  color: theme.colorScheme.tertiary,
                ),
              ),
            ],
          ),
          // SWAP 是整机指标，与上方 CPU / 内存两列无从属关系。此前它是一行
          // 「左标签 + Spacer + 右数值」，标签恰好落在 CPU 图下、数值恰好落在
          // 内存图下，被误读为两列各自的注解。改为带底色的独立区块，并把标签
          // 与数值紧邻排布，从视觉上与上方两列断开。
          if (info.swap.total > 0) ...[
            const SizedBox(height: 16),
            _SwapBar(swap: info.swap),
          ],
        ],
      ),
    );
  }
}

/// 首页仪表用的时分格式（避免在 formatters 中再暴露一个 DateFormat 实例）。
///
/// `.hour` / `.minute` 取的是实例自身时区下的字段，UTC 实例会少算时区偏移，
/// 因此先 `.toLocal()`（对已是本地时区的实例是空操作）。
String formatChartTimeOfDay(DateTime time) {
  final local = time.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}:'
      '${local.second.toString().padLeft(2, '0')}';
}

class _Gauge extends StatelessWidget {
  const _Gauge({
    required this.label,
    required this.percent,
    required this.caption,
    required this.color,
  });

  final String label;
  final double percent;
  final String caption;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = percent.isFinite ? percent.clamp(0.0, 100.0) : 0.0;
    final tint = value >= 90 ? theme.colorScheme.error : color;
    return Column(
      children: [
        SizedBox(
          width: 96,
          height: 96,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: value / 100,
                  strokeWidth: 8,
                  strokeCap: StrokeCap.round,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(tint),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value.toStringAsFixed(1),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: tint,
                      fontFeatures: kTabularFigures,
                    ),
                  ),
                  Text(
                    '%',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: theme.textTheme.titleSmall),
        const SizedBox(height: 2),
        Text(
          caption,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// SWAP（交换分区）使用情况。
///
/// 整机指标，不属于上方 CPU / 内存任一列，因此用独立底色区块承载，
/// 标签与数值紧邻排布，避免被误认为两列的注解。
class _SwapBar extends StatelessWidget {
  const _SwapBar({required this.swap});

  final SwapStat swap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // NaN 通不过 clamp（两次比较都为 false，原样返回），会打挂进度条的断言。
    final percent = swap.usedPercent.isFinite
        ? swap.usedPercent.clamp(0.0, 100.0)
        : 0.0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.swap_horiz,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                'SWAP 交换分区',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${formatBytes(swap.used)} / ${formatBytes(swap.total)}',
                  maxLines: 1,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFeatures: kTabularFigures,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatPercent(swap.usedPercent),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontFeatures: kTabularFigures,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: percent / 100,
              minHeight: 5,
              backgroundColor: theme.colorScheme.surfaceContainerHigh,
            ),
          ),
        ],
      ),
    );
  }
}

class _Trend extends StatelessWidget {
  const _Trend({
    required this.title,
    required this.values,
    required this.color,
  });

  final String title;
  final List<double> values;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        MiniChart(values: values, color: color, minY: 0, maxY: 100, height: 46),
      ],
    );
  }
}
