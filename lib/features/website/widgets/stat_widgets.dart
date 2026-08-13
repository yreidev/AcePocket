import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/website_stat.dart';
import 'formatters.dart';

/// 单个指标卡片（数值 + 名称 + 可选环比）。
class StatMetricTile extends StatelessWidget {
  const StatMetricTile({
    super.key,
    required this.label,
    required this.value,
    this.delta,
    this.deltaPositive = true,
    this.icon,
  });

  final String label;
  final String value;

  /// 环比文案，如 `+12.3%`；为空时不展示。
  final String? delta;

  /// 环比是否为增长（用于着色）。
  final bool deltaPositive;

  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (delta != null && delta!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              '环比 ${delta!}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: deltaPositive ? scheme.primary : scheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 指标卡片网格（每行两列，随宽度自适应）。
class StatMetricGrid extends StatelessWidget {
  const StatMetricGrid({super.key, required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 560 ? 4 : 2;
        const spacing = 8.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final tile in tiles) SizedBox(width: width, child: tile),
          ],
        );
      },
    );
  }
}

/// 统计指标类型（决定折线图取哪个字段）。
enum StatMetric {
  pv('浏览量 PV'),
  uv('访客数 UV'),
  ip('独立 IP'),
  requests('请求数'),
  bandwidth('出站流量'),
  errors('错误数');

  const StatMetric(this.label);

  final String label;

  double valueOf(StatTotals t) => switch (this) {
    StatMetric.pv => t.pv.toDouble(),
    StatMetric.uv => t.uv.toDouble(),
    StatMetric.ip => t.ip.toDouble(),
    StatMetric.requests => t.requests.toDouble(),
    StatMetric.bandwidth => t.bandwidth.toDouble(),
    StatMetric.errors => t.errors.toDouble(),
  };

  String format(double value) => this == StatMetric.bandwidth
      ? formatBytes(value)
      : formatCompactCount(value);
}

/// 时间序列折线图（当前周期 + 可选对比周期）。
class StatSeriesChart extends StatelessWidget {
  const StatSeriesChart({
    super.key,
    required this.series,
    required this.previousSeries,
    required this.metric,
    this.showPrevious = true,
    this.height = 220,
  });

  final List<StatSeriesPoint> series;
  final List<StatSeriesPoint> previousSeries;
  final StatMetric metric;
  final bool showPrevious;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (series.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            '所选时间范围内暂无数据',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final current = <FlSpot>[
      for (var i = 0; i < series.length; i++)
        FlSpot(i.toDouble(), metric.valueOf(series[i].totals)),
    ];
    final previous = <FlSpot>[
      for (var i = 0; i < previousSeries.length && i < series.length; i++)
        FlSpot(i.toDouble(), metric.valueOf(previousSeries[i].totals)),
    ];

    var maxY = 0.0;
    for (final spot in [...current, if (showPrevious) ...previous]) {
      if (spot.y > maxY) maxY = spot.y;
    }
    if (maxY <= 0) maxY = 1;
    maxY *= 1.2;

    final labelStep = (series.length / 6).ceil().clamp(1, series.length);

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (series.length - 1).toDouble(),
          minY: 0,
          maxY: maxY,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxY / 4,
            getDrawingHorizontalLine: (value) =>
                FlLine(color: scheme.outlineVariant, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 48,
                interval: maxY / 4,
                getTitlesWidget: (value, meta) => SideTitleWidget(
                  axisSide: meta.axisSide,
                  space: 4,
                  child: Text(
                    metric.format(value),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontSize: 9,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final index = value.round();
                  if (index < 0 || index >= series.length) {
                    return const SizedBox.shrink();
                  }
                  if (index % labelStep != 0) return const SizedBox.shrink();
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    space: 6,
                    child: Text(
                      series[index].shortLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontSize: 9,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            enabled: true,
            handleBuiltInTouches: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) =>
                  scheme.inverseSurface.withValues(alpha: 0.92),
              tooltipRoundedRadius: 8,
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipItems: (spots) => spots.map((spot) {
                final index = spot.x.round();
                final isPrevious = spot.barIndex == 1;
                final label = isPrevious ? '对比' : '当前';
                final key = index >= 0 && index < series.length
                    ? series[index].key
                    : '';
                return LineTooltipItem(
                  '$label $key  ${metric.format(spot.y)}',
                  TextStyle(
                    color: isPrevious
                        ? scheme.onInverseSurface.withValues(alpha: 0.7)
                        : scheme.onInverseSurface,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                );
              }).toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: current,
              isCurved: true,
              curveSmoothness: 0.25,
              color: scheme.primary,
              barWidth: 2,
              dotData: FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    scheme.primary.withValues(alpha: 0.24),
                    scheme.primary.withValues(alpha: 0.02),
                  ],
                ),
              ),
            ),
            if (showPrevious && previous.isNotEmpty)
              LineChartBarData(
                spots: previous,
                isCurved: true,
                curveSmoothness: 0.25,
                color: scheme.outline,
                barWidth: 1.5,
                dashArray: const [4, 4],
                dotData: FlDotData(show: false),
              ),
          ],
        ),
      ),
    );
  }
}

/// 排行条形列表项：名称 + 占比进度条 + 数值。
class StatRankBar extends StatelessWidget {
  const StatRankBar({
    super.key,
    required this.label,
    required this.value,
    required this.ratio,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final String label;

  /// 主数值文案。
  final String value;

  /// 相对最大值的占比（0-1）。
  final double ratio;

  final String? subtitle;
  final String? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              const SizedBox(width: 8),
              Text(value, style: theme.textTheme.labelLarge),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio.isFinite ? ratio.clamp(0.0, 1.0) : 0,
              minHeight: 6,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
          if (subtitle != null || trailing != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                if (subtitle != null)
                  Expanded(
                    child: Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  const Spacer(),
                if (trailing != null)
                  Text(
                    trailing!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(onTap: onTap, child: content);
  }
}

/// 状态码分布（2xx/3xx/4xx/5xx）。
class StatusCodeBars extends StatelessWidget {
  const StatusCodeBars({super.key, required this.totals});

  final StatTotals totals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final entries = <(String, int, Color)>[
      ('2xx 成功', totals.status2xx, scheme.primary),
      ('3xx 跳转', totals.status3xx, scheme.tertiary),
      ('4xx 客户端错误', totals.status4xx, scheme.secondary),
      ('5xx 服务端错误', totals.status5xx, scheme.error),
    ];
    final total = entries.fold<int>(0, (sum, e) => sum + e.$2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(entry.$1, style: theme.textTheme.bodySmall),
                    ),
                    Text(
                      '${formatCount(entry.$2)}'
                      '${total > 0 ? '（${(entry.$2 / total * 100).toStringAsFixed(1)}%）' : ''}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0 : entry.$2 / total,
                    minHeight: 6,
                    color: entry.$3,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
