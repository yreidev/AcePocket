import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'more_usage_store.dart';

/// 「更多」页入口使用记录（path -> 记录），供「常用置顶」分组消费。
final moreUsageProvider =
    NotifierProvider<MoreUsageNotifier, Map<String, MoreUsageRecord>>(
      MoreUsageNotifier.new,
    );

class MoreUsageNotifier extends Notifier<Map<String, MoreUsageRecord>> {
  @override
  Map<String, MoreUsageRecord> build() {
    // MoreUsageStore 在 main() 中已 init，此处可同步读取；未 init 时为空 map。
    return MoreUsageStore.instance.records;
  }

  /// 记录一次入口点击并持久化，再刷新为新快照。
  Future<void> recordTap(String path) async {
    await MoreUsageStore.instance.recordTap(path);
    state = MoreUsageStore.instance.records;
  }

  /// 清空全部使用记录并持久化，state 置空。
  Future<void> clearAll() async {
    await MoreUsageStore.instance.clear();
    state = MoreUsageStore.instance.records;
  }
}
