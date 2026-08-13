import 'dart:math' as math;

import 'package:acepocket/core/utils/downsample.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('lttbIndexes', () {
    test('数据量不超过阈值时原样返回全部下标', () {
      final values = List<double>.generate(100, (i) => i.toDouble());
      final indexes = lttbIndexes(values, 300);
      expect(indexes, List<int>.generate(100, (i) => i));
    });

    test('抽样到指定点数且保留首尾点', () {
      final values = List<double>.generate(
        10000,
        (i) => math.sin(i / 50) * 100,
      );
      final indexes = lttbIndexes(values, 300);
      expect(indexes.length, 300);
      expect(indexes.first, 0);
      expect(indexes.last, 9999);
    });

    test('下标严格升序（无重复、无乱序）', () {
      final random = math.Random(42);
      final values = List<double>.generate(
        5000,
        (_) => random.nextDouble() * 1000,
      );
      final indexes = lttbIndexes(values, 250);
      expect(indexes.length, 250);
      for (var i = 1; i < indexes.length; i++) {
        expect(indexes[i], greaterThan(indexes[i - 1]));
      }
    });

    test('阈值为 2 时只保留首尾点', () {
      final values = List<double>.generate(100, (i) => i.toDouble());
      expect(lttbIndexes(values, 2), [0, 99]);
    });

    test('空序列与单点序列', () {
      expect(lttbIndexes(const [], 300), isEmpty);
      expect(lttbIndexes(const [1.0], 300), [0]);
    });

    test('保留明显的尖峰点', () {
      // 平坦序列中在已知位置放一个尖峰，LTTB 必须选中它。
      final values = List<double>.filled(10000, 10.0);
      values[3456] = 500.0;
      final indexes = lttbIndexes(values, 300);
      expect(indexes, contains(3456));
    });
  });

  group('downsampleIndexes', () {
    test('数据量不超过阈值时原样返回全部下标', () {
      final indexes = downsampleIndexes(
        length: 200,
        seriesValues: [List<double>.generate(200, (i) => i.toDouble())],
        threshold: 300,
      );
      expect(indexes, List<int>.generate(200, (i) => i));
    });

    test('输出点数约为阈值：不少于阈值、不超过阈值 + 2 × 序列数', () {
      final random = math.Random(7);
      final series = [
        List<double>.generate(43200, (_) => random.nextDouble() * 100),
        List<double>.generate(43200, (_) => random.nextDouble() * 100),
        List<double>.generate(43200, (_) => random.nextDouble() * 100),
      ];
      final indexes = downsampleIndexes(
        length: 43200,
        seriesValues: series,
        threshold: 300,
      );
      expect(indexes.length, greaterThanOrEqualTo(300));
      expect(indexes.length, lessThanOrEqualTo(300 + 2 * series.length));
    });

    test('保留首尾点', () {
      final values = List<double>.generate(10000, (i) => math.cos(i / 30));
      final indexes = downsampleIndexes(
        length: 10000,
        seriesValues: [values],
        threshold: 300,
      );
      expect(indexes.first, 0);
      expect(indexes.last, 9999);
    });

    test('每条序列的全局最大 / 最小值点必然保留', () {
      // 序列 A 在 1234 处有全局最大值、7890 处有全局最小值；
      // 序列 B 的极值在另外两个位置。四个极值点都必须出现在结果中。
      final a = List<double>.generate(43200, (i) => math.sin(i / 100) * 10);
      a[1234] = 999.0; // A 的全局最大值
      a[7890] = -999.0; // A 的全局最小值
      final b = List<double>.generate(43200, (i) => math.cos(i / 100) * 10);
      b[22222] = 888.0; // B 的全局最大值
      b[33333] = -888.0; // B 的全局最小值

      final indexes = downsampleIndexes(
        length: 43200,
        seriesValues: [a, b],
        threshold: 300,
      );
      expect(indexes, contains(1234));
      expect(indexes, contains(7890));
      expect(indexes, contains(22222));
      expect(indexes, contains(33333));
    });

    test('下标升序且不重复', () {
      final random = math.Random(11);
      final indexes = downsampleIndexes(
        length: 8000,
        seriesValues: [
          List<double>.generate(8000, (_) => random.nextDouble()),
          List<double>.generate(8000, (_) => random.nextDouble()),
        ],
        threshold: 300,
      );
      for (var i = 1; i < indexes.length; i++) {
        expect(indexes[i], greaterThan(indexes[i - 1]));
      }
    });

    test('序列长度短于 length 时不越界', () {
      final indexes = downsampleIndexes(
        length: 1000,
        seriesValues: [
          List<double>.generate(1000, (i) => i.toDouble()),
          List<double>.generate(500, (i) => i.toDouble()), // 较短的序列
        ],
        threshold: 100,
      );
      expect(indexes.first, 0);
      expect(indexes.last, 999);
      expect(indexes.every((i) => i >= 0 && i < 1000), isTrue);
    });

    test('length 为 0 时返回空', () {
      expect(
        downsampleIndexes(length: 0, seriesValues: const [], threshold: 300),
        isEmpty,
      );
    });
  });
}
