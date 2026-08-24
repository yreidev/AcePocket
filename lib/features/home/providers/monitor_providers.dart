import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/storage/server_store.dart';
import '../models/monitor_models.dart';
import '../repo/monitor_repo.dart';

/// 监控 Repository（依赖当前选中服务器的 ApiClient）。
final monitorRepoProvider = Provider<MonitorRepository>((ref) {
  return MonitorRepository(ref.watch(apiClientProvider));
});

/// 历史监控时间范围选项。
enum MonitorRange {
  today('今天'),
  yesterday('昨天'),
  last7d('近 7 天'),
  last30d('近 30 天');

  const MonitorRange(this.label);

  final String label;

  /// 计算毫秒级 start / end（与面板前端 SystemView 的取值逻辑一致：
  /// 今天 = 今日 0 点至今；昨天 = 昨日 0 点到今日 0 点；近 N 天 = N 天前 0 点至今）。
  ({int start, int end}) resolve() {
    final now = DateTime.now();
    final todayStart = DateTime(
      now.year,
      now.month,
      now.day,
    ).millisecondsSinceEpoch;
    const dayMs = 24 * 60 * 60 * 1000;
    switch (this) {
      case MonitorRange.today:
        return (start: todayStart, end: now.millisecondsSinceEpoch);
      case MonitorRange.yesterday:
        return (start: todayStart - dayMs, end: todayStart);
      case MonitorRange.last7d:
        return (start: todayStart - 7 * dayMs, end: now.millisecondsSinceEpoch);
      case MonitorRange.last30d:
        return (
          start: todayStart - 30 * dayMs,
          end: now.millisecondsSinceEpoch,
        );
    }
  }

  /// 该范围是否跨天（决定图表时间轴标签是否带日期）。
  bool get spansMultipleDays =>
      this == MonitorRange.last7d || this == MonitorRange.last30d;
}

/// 当前选中的时间范围。
final monitorRangeProvider = StateProvider.autoDispose<MonitorRange>(
  (ref) => MonitorRange.today,
);

/// 历史监控数据（随时间范围变化自动重新加载）。
final monitorDetailProvider = FutureProvider.autoDispose<MonitorDetail>((ref) {
  final range = ref.watch(monitorRangeProvider).resolve();
  return ref
      .watch(monitorRepoProvider)
      .list(start: range.start, end: range.end);
});

/// 监控设置。
final monitorSettingProvider = FutureProvider.autoDispose<MonitorSetting>((
  ref,
) {
  return ref.watch(monitorRepoProvider).setting();
});

/// 网络图表当前选中的网卡名（null = 数据中的第一块网卡）。
final monitorNetDeviceProvider = StateProvider.autoDispose<String?>(
  (ref) => null,
);

/// 磁盘 IO 图表当前选中的磁盘名（null = 数据中的第一块磁盘）。
final monitorDiskDeviceProvider = StateProvider.autoDispose<String?>(
  (ref) => null,
);
