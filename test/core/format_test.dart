import 'package:acepocket/core/utils/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatBytes', () {
    test('常规量级按 1024 进制换算', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1024), '1.00 KB');
      expect(formatBytes(1536), '1.50 KB');
      expect(formatBytes(1024 * 1024), '1.00 MB');
      expect(formatBytes(1024 * 1024 * 1024), '1.00 GB');
      expect(formatBytes(1.25 * 1024 * 1024 * 1024), '1.25 GB');
    });

    test('0 < x < 1 不抛异常（旧实现 log/floor 得 -1 会 RangeError）', () {
      expect(() => formatBytes(0.5), returnsNormally);
      expect(formatBytes(0.5), '1 B');
      expect(formatBytes(0.4), '0 B');
      expect(formatBytes(0.0001), '0 B');
      expect(formatBytes(0.999), '1 B');
    });

    test('负数 / NaN / Infinity 一律兜底为 0 B', () {
      expect(formatBytes(-1), '0 B');
      expect(formatBytes(-1024 * 1024), '0 B');
      expect(formatBytes(double.nan), '0 B');
      expect(formatBytes(double.infinity), '0 B');
      expect(formatBytes(double.negativeInfinity), '0 B');
    });

    test('超大数值停在最高单位而非越界', () {
      final huge = 1024.0 * 1024 * 1024 * 1024 * 1024 * 1024 * 1024 * 1024;
      expect(() => formatBytes(huge), returnsNormally);
      expect(formatBytes(huge), endsWith(' EB'));
      expect(formatBytes(double.maxFinite), endsWith(' EB'));
    });

    test('fractionDigits 生效且越界值被钳制而非抛异常', () {
      expect(formatBytes(1536, fractionDigits: 0), '2 KB');
      expect(formatBytes(1536, fractionDigits: 1), '1.5 KB');
      expect(() => formatBytes(1536, fractionDigits: -3), returnsNormally);
      expect(() => formatBytes(1536, fractionDigits: 99), returnsNormally);
    });

    test('字节单位始终取整（小数没有意义）', () {
      expect(formatBytes(999.6), '1000 B');
      expect(formatBytes(1023.4), '1023 B');
    });
  });

  group('formatBytesRate', () {
    test('在体积后追加 /s，默认一位小数', () {
      expect(formatBytesRate(0), '0 B/s');
      expect(formatBytesRate(1536), '1.5 KB/s');
      expect(formatBytesRate(1024 * 1024), '1.0 MB/s');
    });

    test('异常输入不抛异常', () {
      expect(formatBytesRate(0.5), '1 B/s');
      expect(formatBytesRate(-1), '0 B/s');
      expect(formatBytesRate(double.nan), '0 B/s');
      expect(formatBytesRate(double.infinity), '0 B/s');
    });
  });

  group('formatPercent', () {
    test('常规值保留一位小数', () {
      expect(formatPercent(0), '0.0%');
      expect(formatPercent(42.34), '42.3%');
      expect(formatPercent(100), '100.0%');
      expect(formatPercent(85, fractionDigits: 0), '85%');
      expect(formatPercent(85.5, fractionDigits: 2), '85.50%');
    });

    test('超出 0-100 的值被钳制', () {
      expect(formatPercent(100.4), '100.0%');
      expect(formatPercent(1000), '100.0%');
      expect(formatPercent(-5), '0.0%');
      expect(formatPercent(double.infinity), '100.0%');
      expect(formatPercent(double.negativeInfinity), '0.0%');
    });

    test('NaN 按 0 处理且不抛异常', () {
      expect(() => formatPercent(double.nan), returnsNormally);
      expect(formatPercent(double.nan), '0.0%');
    });
  });

  group('formatDuration', () {
    test('零与毫秒级', () {
      expect(formatDuration(Duration.zero), '0 秒');
      expect(formatDuration(const Duration(milliseconds: 320)), '320 毫秒');
    });

    test('秒 / 分 / 小时 / 天最多两级单位', () {
      expect(formatDuration(const Duration(seconds: 45)), '45 秒');
      expect(formatDuration(const Duration(minutes: 5)), '5 分');
      expect(
        formatDuration(const Duration(minutes: 5, seconds: 20)),
        '5 分 20 秒',
      );
      expect(formatDuration(const Duration(hours: 2)), '2 小时');
      expect(
        formatDuration(const Duration(hours: 2, minutes: 30, seconds: 9)),
        '2 小时 30 分',
      );
      expect(formatDuration(const Duration(days: 3)), '3 天');
      expect(
        formatDuration(const Duration(days: 3, hours: 4, minutes: 59)),
        '3 天 4 小时',
      );
    });

    test('负时长取绝对值并加负号', () {
      expect(formatDuration(const Duration(seconds: -45)), '-45 秒');
      expect(
        formatDuration(const Duration(hours: -1, minutes: -30)),
        '-1 小时 30 分',
      );
    });
  });

  group('formatDateTime / formatRelative', () {
    test('null 展示占位', () {
      expect(formatDateTime(null), '-');
      expect(formatRelative(null), '-');
    });

    test('本地时间格式为 yyyy-MM-dd HH:mm:ss', () {
      final time = DateTime(2026, 8, 13, 9, 8, 7);
      expect(formatDateTime(time), '2026-08-13 09:08:07');
    });

    test('刚刚 / 分钟前', () {
      expect(formatRelative(DateTime.now()), '刚刚');
      expect(
        formatRelative(DateTime.now().subtract(const Duration(minutes: 3))),
        '3 分钟前',
      );
    });
  });
}
