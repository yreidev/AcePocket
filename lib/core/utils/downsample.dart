/// 折线图抽样工具。
///
/// 历史监控按分钟采样时，30 天范围可达 4 万+ 数据点/曲线，直接交给
/// fl_chart 绘制会导致滑动与 tooltip 明显掉帧，因此绘制前先抽样到
/// 几百个点。算法采用 LTTB（Largest-Triangle-Three-Buckets）：
/// 把序列按目标点数分桶，每桶选出与「上一个已选点」和「下一桶均值点」
/// 构成三角形面积最大的点，能最大限度保留曲线的视觉形状。
///
/// LTTB 倾向于保留局部拐点，但不保证全局最值一定入选；峰值恰恰是
/// 监控图表最重要的信息，因此 [downsampleIndexes] 在 LTTB 结果之上
/// 强制并入每条序列的全局最大值 / 最小值下标，确保「最高点 / 最低点」
/// 不会被抽样抹掉。
library;

import 'dart:collection';

/// 对等距 X 轴的数值序列 [values] 做 LTTB 抽样，返回保留点的下标（升序）。
///
/// - [threshold] 为目标点数（>= 2）；
/// - 结果恒包含首点（下标 0）与尾点（下标 `values.length - 1`）；
/// - `values.length <= threshold` 时返回全部下标（不抽样）。
List<int> lttbIndexes(List<double> values, int threshold) {
  final n = values.length;
  if (n == 0) return const [];
  if (threshold >= n) return List<int>.generate(n, (i) => i);
  if (threshold <= 2 || n <= 2) return n == 1 ? [0] : [0, n - 1];

  final sampled = <int>[0];
  // 除去首尾点后，中间 n-2 个点分成 threshold-2 个桶。
  final every = (n - 2) / (threshold - 2);
  var a = 0; // 上一个已选点的下标。

  for (var i = 0; i < threshold - 2; i++) {
    // 下一桶的均值点（最后一桶的“下一桶”为尾点所在区间）。
    var avgRangeStart = ((i + 1) * every).floor() + 1;
    var avgRangeEnd = ((i + 2) * every).floor() + 1;
    if (avgRangeEnd > n) avgRangeEnd = n;
    final avgRangeLength = avgRangeEnd - avgRangeStart;
    var avgX = 0.0;
    var avgY = 0.0;
    for (var j = avgRangeStart; j < avgRangeEnd; j++) {
      avgX += j;
      avgY += values[j];
    }
    if (avgRangeLength > 0) {
      avgX /= avgRangeLength;
      avgY /= avgRangeLength;
    }

    // 当前桶范围。
    final rangeOffs = (i * every).floor() + 1;
    var rangeTo = ((i + 1) * every).floor() + 1;
    if (rangeTo > n - 1) rangeTo = n - 1;

    final ax = a.toDouble();
    final ay = values[a];

    var maxArea = -1.0;
    var maxAreaIndex = rangeOffs;
    for (var j = rangeOffs; j < rangeTo; j++) {
      // 三角形面积（× 2，比较大小无需除以 2）。
      final area =
          ((ax - avgX) * (values[j] - ay) - (ax - j) * (avgY - ay)).abs();
      if (area > maxArea) {
        maxArea = area;
        maxAreaIndex = j;
      }
    }
    sampled.add(maxAreaIndex);
    a = maxAreaIndex;
  }

  sampled.add(n - 1);
  return sampled;
}

/// 多条共享 X 轴的序列联合抽样，返回保留点的下标（升序、去重）。
///
/// 只考虑各序列前 [length] 个点（[length] 通常取时间轴与各序列长度的
/// 最小值）。`length <= threshold` 时返回全部下标。
///
/// 抽样策略：
/// 1. 以各序列的逐点均值作为“驱动序列”跑 LTTB，得到约 [threshold] 个
///    形状代表点（首尾点必含）；
/// 2. 再并入**每条**序列在 `[0, length)` 内全局最大值与最小值的下标。
///
/// 因此结果点数最多为 `threshold + 2 × 序列数`，且每条序列的最高点与
/// 最低点必然保留 —— 这正是监控图表不能丢的峰值信息。
List<int> downsampleIndexes({
  required int length,
  required List<List<double>> seriesValues,
  int threshold = 300,
}) {
  if (length <= 0) return const [];
  if (length <= threshold) return List<int>.generate(length, (i) => i);

  // 驱动序列：各序列的逐点均值（序列不足 length 的点按已有序列平均）。
  final driver = List<double>.generate(length, (i) {
    var sum = 0.0;
    var count = 0;
    for (final s in seriesValues) {
      if (i < s.length) {
        sum += s[i];
        count++;
      }
    }
    return count == 0 ? 0 : sum / count;
  });

  final picked = SplayTreeSet<int>.of(lttbIndexes(driver, threshold));

  // 强制保留每条序列的全局极值点。
  for (final s in seriesValues) {
    final limit = length < s.length ? length : s.length;
    if (limit == 0) continue;
    var minIndex = 0;
    var maxIndex = 0;
    for (var i = 1; i < limit; i++) {
      if (s[i] < s[minIndex]) minIndex = i;
      if (s[i] > s[maxIndex]) maxIndex = i;
    }
    picked
      ..add(minIndex)
      ..add(maxIndex);
  }

  return picked.toList();
}
