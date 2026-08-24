import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/downsample.dart';
import '../../../core/widgets/section_card.dart';
import 'formatters.dart';

/// 历史监控图表的一条数据序列。
class ChartSeries {
  const ChartSeries({
    required this.name,
    required this.values,
    required this.color,
  });

  final String name;
  final List<double> values;
  final Color color;
}

/// 历史监控折线图卡片：多序列 + 图例 + 触摸提示 + 时间轴。
class MonitorChartCard extends StatelessWidget {
  const MonitorChartCard({
    super.key,
    required this.title,
    required this.times,
    required this.series,
    required this.valueFormatter,
    this.trailing,
    this.subtitle,
    this.minY,
    this.maxY,
    this.height = 200,
  });

  final String title;

  /// 时间标签（与序列一一对应，格式 `yyyy-MM-dd HH:mm:ss`）。
  final List<String> times;

  final List<ChartSeries> series;

  /// 数值格式化（用于纵轴刻度与提示气泡）。
  final String Function(double value) valueFormatter;

  /// 标题行尾部组件（如网卡下拉选择）。
  final Widget? trailing;

  /// 标题下方补充说明（如内存总量）。
  final String? subtitle;

  final double? minY;
  final double? maxY;
  final double height;

  /// 抽样后交给 fl_chart 绘制的目标点数上限。
  ///
  /// 30 天 × 分钟级采样约 4.3 万点/曲线，全量绘制会导致滑动与 tooltip
  /// 明显掉帧；超过该值时先做 LTTB 抽样（并强制保留各序列全局极值点，
  /// 见 [downsampleIndexes]），实际点数最多为该值 + 2 × 序列数。
  static const int _maxPoints = 300;

  int get _length {
    var length = times.length;
    for (final s in series) {
      length = math.min(length, s.values.length);
    }
    return length;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final withDate = _spansMultipleDays;

    // 数据点过多时先抽样再绘制，峰值（各序列全局最值）保证保留。
    var times = this.times;
    var series = this.series;
    String? sampleNote;
    final rawLength = _length;
    if (rawLength > _maxPoints) {
      final indexes = downsampleIndexes(
        length: rawLength,
        seriesValues: [for (final s in series) s.values],
        threshold: _maxPoints,
      );
      times = [for (final i in indexes) times[i]];
      series = [
        for (final s in series)
          ChartSeries(
            name: s.name,
            values: [for (final i in indexes) s.values[i]],
            color: s.color,
          ),
      ];
      sampleNote = '已抽样显示，共 ${indexes.length} 个采样点';
    }
    final length = math.min(rawLength, times.length);

    final subtitleText = [?subtitle, ?sampleNote].join(' · ');

    if (length < 2) {
      // 只有 0 / 1 个采样点时画不出折线，但唯一的那个采样值仍是有效信息，
      // 直接以文字列出，避免「什么都看不到」。
      final single = length == 1;
      return SectionCard(
        title: title,
        trailing: trailing,
        child: SizedBox(
          height: 96,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  single ? '该时间段只采集到 1 个数据点，暂时画不出趋势' : '该时间段没有采集到监控数据',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (single) ...[
                  const SizedBox(height: 8),
                  Text(
                    [
                      for (final s in series)
                        '${s.name} ${valueFormatter(s.values.first)}',
                    ].join('  ·  '),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFeatures: kTabularFigures,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    var bottom = minY ?? double.infinity;
    var top = maxY ?? double.negativeInfinity;
    if (minY == null || maxY == null) {
      for (final s in series) {
        for (var i = 0; i < length; i++) {
          final v = s.values[i];
          if (minY == null && v < bottom) bottom = v;
          if (maxY == null && v > top) top = v;
        }
      }
    }
    if (!bottom.isFinite) bottom = 0;
    if (!top.isFinite) top = 1;
    if (top - bottom < 1e-9) {
      top = bottom + (bottom.abs() < 1e-9 ? 1 : bottom.abs() * 0.2);
    }
    final padding = (top - bottom) * 0.1;
    if (maxY == null) top += padding;
    if (minY == null) bottom = math.max(0, bottom - padding);

    final labelInterval = math.max(1, (length / 4).ceil()).toDouble();

    // 提示气泡：底色与文字色成对取自 ColorScheme，Material 3 保证这对颜色
    // 在深浅两种主题下都满足文字对比度要求。底色不再加透明度——半透明会把
    // 身后的曲线透进来，进一步压低实际对比度。
    final tooltipBackground = theme.colorScheme.inverseSurface;
    final tooltipForeground = theme.colorScheme.onInverseSurface;

    return SectionCard(
      title: title,
      trailing: trailing,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (subtitleText.isNotEmpty) ...[
            Text(
              subtitleText,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
          ],
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              for (final s in series)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 3,
                      decoration: BoxDecoration(
                        color: s.color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      s.name,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          // 折线图对读屏用户完全不可见（fl_chart 只画 CustomPaint，语义树里
          // 什么都没有）。这里把「时间范围 + 每条序列的当前值 / 峰值 / 谷值」
          // 汇总成一句话挂到语义节点上，作为图形的文字替代；图表本身用
          // ExcludeSemantics 兜住，避免日后 fl_chart 加入语义时重复播报。
          Semantics(
            container: true,
            label: _semanticsLabel(rawLength),
            child: ExcludeSemantics(
              child: SizedBox(
                height: height,
                child: LineChart(
                  LineChartData(
                    minX: 0,
                    maxX: (length - 1).toDouble(),
                    minY: bottom,
                    maxY: top,
                    clipData: FlClipData.all(),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: (top - bottom) / 4,
                      getDrawingHorizontalLine: (value) => FlLine(
                        color: theme.colorScheme.outlineVariant,
                        strokeWidth: 1,
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      show: true,
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 52,
                          interval: (top - bottom) / 4,
                          getTitlesWidget: (value, meta) => SideTitleWidget(
                            meta: meta,
                            space: 6,
                            child: Text(
                              valueFormatter(value),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 9,
                              ),
                            ),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 28,
                          interval: labelInterval,
                          getTitlesWidget: (value, meta) {
                            final index = value.round();
                            if (index < 0 || index >= length) {
                              return const SizedBox.shrink();
                            }
                            return SideTitleWidget(
                              meta: meta,
                              space: 6,
                              child: Text(
                                formatChartTime(
                                  times[index],
                                  withDate: withDate,
                                ),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
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
                        getTooltipColor: (_) => tooltipBackground,
                        tooltipBorderRadius: BorderRadius.circular(8),
                        fitInsideHorizontally: true,
                        fitInsideVertically: true,
                        getTooltipItems: (touchedSpots) {
                          // 文字一律用与气泡底色配对的 onInverseSurface——此前用系列色
                          // 画在 inverseSurface 上，深浅两种主题下核心数值都读不清；
                          // 系列区分改由行首的色块承担（色块是图形，只需 3:1 对比度，
                          // 且与图例的色块一一对应）。
                          final labelStyle = TextStyle(
                            color: tooltipForeground.withValues(alpha: 0.82),
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                          );
                          final valueStyle = TextStyle(
                            color: tooltipForeground,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            fontFeatures: kTabularFigures,
                          );
                          final timeStyle = TextStyle(
                            color: tooltipForeground.withValues(alpha: 0.82),
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                            fontFeatures: kTabularFigures,
                          );

                          final items = <LineTooltipItem>[];
                          for (var i = 0; i < touchedSpots.length; i++) {
                            final spot = touchedSpots[i];
                            final s = spot.barIndex < series.length
                                ? series[spot.barIndex]
                                : null;
                            final index = spot.spotIndex;
                            final prefix =
                                i == 0 && index >= 0 && index < times.length
                                ? '${formatTooltipTime(times[index])}\n'
                                : '';
                            items.add(
                              LineTooltipItem(
                                prefix,
                                timeStyle,
                                textAlign: TextAlign.left,
                                children: [
                                  if (s != null)
                                    TextSpan(
                                      text: '■ ',
                                      style: TextStyle(
                                        color: _readableSwatch(
                                          s.color,
                                          tooltipBackground,
                                          tooltipForeground,
                                        ),
                                        fontSize: 11,
                                      ),
                                    ),
                                  if (s != null)
                                    TextSpan(
                                      text: '${s.name}  ',
                                      style: labelStyle,
                                    ),
                                  TextSpan(
                                    text: valueFormatter(spot.y),
                                    style: valueStyle,
                                  ),
                                ],
                              ),
                            );
                          }
                          return items;
                        },
                      ),
                    ),
                    lineBarsData: [
                      for (final s in series)
                        LineChartBarData(
                          spots: [
                            for (var i = 0; i < length; i++)
                              FlSpot(i.toDouble(), s.values[i]),
                          ],
                          isCurved: true,
                          curveSmoothness: 0.2,
                          preventCurveOverShooting: true,
                          color: s.color,
                          barWidth: 2,
                          dotData: FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: series.length == 1,
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                s.color.withValues(alpha: 0.24),
                                s.color.withValues(alpha: 0.02),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 数据是否跨天（决定时间轴标签是否带日期）。
  bool get _spansMultipleDays {
    if (times.length < 2) return false;
    final first = parseMonitorTime(times.first);
    final last = parseMonitorTime(times.last);
    if (first == null || last == null) return false;
    return first.year != last.year ||
        first.month != last.month ||
        first.day != last.day;
  }

  /// 图表的文字替代：时间范围 + 每条序列的当前值 / 峰值（含出现时刻）/ 谷值。
  ///
  /// 用**抽样前**的原始序列统计，保证峰值与其时刻精确到实际采样点；
  /// 时刻一律带日期（读屏没有横轴做上下文）。
  String _semanticsLabel(int length) {
    if (length < 2) return '$title 趋势图，数据点不足，无法绘制';

    String at(int index) => index >= 0 && index < times.length
        ? formatTooltipTime(times[index])
        : '未知时间';

    final buffer = StringBuffer('$title 趋势图，')
      ..write('时间范围 ${at(0)} 至 ${at(length - 1)}，')
      ..write('共 $length 个数据点。');

    for (final s in series) {
      final count = math.min(length, s.values.length);
      if (count == 0) continue;
      var maxIndex = 0;
      var minIndex = 0;
      for (var i = 1; i < count; i++) {
        if (s.values[i] > s.values[maxIndex]) maxIndex = i;
        if (s.values[i] < s.values[minIndex]) minIndex = i;
      }
      buffer
        ..write('${s.name}：当前 ${valueFormatter(s.values[count - 1])}，')
        ..write(
          '峰值 ${valueFormatter(s.values[maxIndex])} '
          '出现在 ${at(maxIndex)}，',
        )
        ..write('最低 ${valueFormatter(s.values[minIndex])}。');
    }
    return buffer.toString();
  }
}

/// 提示气泡里的系列色块颜色。
///
/// 气泡底色是 `inverseSurface`（浅色主题下接近黑、深色主题下接近白），
/// 而系列色是为卡片底色（`surfaceContainerLow`）挑的，直接画上去可能糊成
/// 一团。这里在保留色相的前提下朝前景色混合，直到对比度达到 Material
/// 对非文字图形的下限 3:1。
Color _readableSwatch(Color color, Color background, Color foreground) {
  var result = color;
  for (var step = 1; step <= 10; step++) {
    if (_contrastRatio(result, background) >= 3.0) break;
    result = Color.lerp(color, foreground, step / 10)!;
  }
  return result;
}

/// WCAG 相对亮度对比度（1.0 - 21.0）。
double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final high = math.max(la, lb);
  final low = math.min(la, lb);
  return (high + 0.05) / (low + 0.05);
}
