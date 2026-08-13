import 'package:acepocket/core/api/api_exception.dart';
import 'package:acepocket/features/apps/widgets/formatters.dart';
import 'package:acepocket/features/apps/widgets/paged_list_footer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatCpuPercent', () {
    test('多核进程超过 100% 时不被钳制', () {
      // gopsutil 的 CPUPercent 是 CPU 时间 / 墙钟时间，8 核跑满即 800%。
      expect(formatCpuPercent(812.5), '812.5%');
    });

    test('异常输入兜底为 0.0%', () {
      expect(formatCpuPercent(double.nan), '0.0%');
      expect(formatCpuPercent(double.infinity), '0.0%');
      expect(formatCpuPercent(-1), '0.0%');
    });
  });

  group('formatBytes', () {
    test('小于 1 字节与 0 不抛异常', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(0.4), '0 B');
    });

    test('大数值按 1024 进制换算', () {
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1024 * 1024 * 1024), '1.0 GB');
    });
  });

  testWidgets('加载更多失败时展示原因与重试按钮，不再无限转圈', (tester) async {
    var retried = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PagedListFooter(
            hasMore: true,
            total: 100,
            error: const ApiException('连接超时'),
            onRetry: () => retried++,
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('连接超时'), findsOneWidget);

    await tester.tap(find.text('重试'));
    expect(retried, 1);
  });

  testWidgets('还有下一页且无错误时展示进度指示', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PagedListFooter(hasMore: true, total: 100)),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
