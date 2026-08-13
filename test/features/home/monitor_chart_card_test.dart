import 'package:acepocket/features/home/widgets/monitor_chart_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 把卡片放进一个最小可用的 App 里渲染。
Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

const _times = <String>[
  '2024-05-01 10:00:00',
  '2024-05-01 10:01:00',
  '2024-05-01 10:02:00',
  '2024-05-01 10:03:00',
];

void main() {
  testWidgets('图表给读屏用户提供文字替代：范围 + 当前值 + 峰值及其时刻', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        MonitorChartCard(
          title: 'CPU 使用率',
          times: _times,
          minY: 0,
          maxY: 100,
          valueFormatter: (v) => '${v.toStringAsFixed(0)}%',
          series: const [
            ChartSeries(
              name: 'CPU',
              values: [12, 78, 30, 45],
              color: Color(0xFF6750A4),
            ),
          ],
        ),
      ),
    );

    // 语义树里必须能找到概括整张图的那句话。
    final labels = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .map((e) => e.properties.label)
        .whereType<String>()
        .toList();
    final summary = labels.firstWhere(
      (e) => e.contains('CPU 使用率 趋势图'),
      orElse: () => '',
    );

    expect(summary, isNotEmpty, reason: '图表没有任何文字替代，读屏用户完全读不到');
    expect(summary, contains('05-01 10:00'));
    expect(summary, contains('05-01 10:03'));
    // 当前值取最后一个采样点，峰值取全局最大值并带出其时刻。
    expect(summary, contains('当前 45%'));
    expect(summary, contains('峰值 78%'));
    expect(summary, contains('出现在 05-01 10:01'));
    expect(summary, contains('最低 12%'));

    handle.dispose();
  });

  testWidgets('只有一个采样点时不画空图，直接把该点的数值列出来', (tester) async {
    await tester.pumpWidget(
      _host(
        MonitorChartCard(
          title: '系统负载',
          times: const ['2024-05-01 10:00:00'],
          minY: 0,
          valueFormatter: (v) => v.toStringAsFixed(2),
          series: const [
            ChartSeries(name: '1 分钟', values: [0.87], color: Color(0xFF6750A4)),
          ],
        ),
      ),
    );

    expect(find.textContaining('只采集到 1 个数据点'), findsOneWidget);
    expect(find.text('1 分钟 0.87'), findsOneWidget);
  });

  testWidgets('完全没有数据时给出明确说明而不是空白卡片', (tester) async {
    await tester.pumpWidget(
      _host(
        MonitorChartCard(
          title: '内存使用',
          times: const [],
          valueFormatter: (v) => v.toStringAsFixed(0),
          series: const [
            ChartSeries(name: '已用', values: [], color: Color(0xFF6750A4)),
          ],
        ),
      ),
    );

    expect(find.textContaining('没有采集到监控数据'), findsOneWidget);
  });

  testWidgets('全部采样值相同（恒为 0）时仍能正常绘制，不因刻度间隔为 0 崩溃', (tester) async {
    await tester.pumpWidget(
      _host(
        MonitorChartCard(
          title: '网络速率',
          times: _times,
          minY: 0,
          valueFormatter: (v) => v.toStringAsFixed(1),
          series: const [
            ChartSeries(
              name: '上行',
              values: [0, 0, 0, 0],
              color: Color(0xFF6750A4),
            ),
          ],
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('上行'), findsOneWidget);
  });
}
