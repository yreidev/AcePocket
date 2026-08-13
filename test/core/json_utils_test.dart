import 'package:acepocket/core/utils/json_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('jsonInt', () {
    test('兼容 int / 小数 / 数字字符串', () {
      expect(jsonInt(3), 3);
      expect(jsonInt(3.9), 3);
      expect(jsonInt('12'), 12);
      expect(jsonInt('1.5'), 1);
      expect(jsonInt(null, 7), 7);
      expect(jsonInt('x', 7), 7);
    });
  });

  group('jsonBool', () {
    test('兼容 bool / 数字 / 字符串，缺省走 fallback', () {
      expect(jsonBool(true), isTrue);
      expect(jsonBool(1), isTrue);
      expect(jsonBool('true'), isTrue);
      expect(jsonBool('1'), isTrue);
      expect(jsonBool('yes'), isTrue);
      expect(jsonBool(false), isFalse);
      expect(jsonBool(0), isFalse);
      expect(jsonBool('false'), isFalse);
      expect(jsonBool(null), isFalse);
      expect(jsonBool(null, true), isTrue);
      expect(jsonBool('status', true), isTrue);
    });
  });

  group('jsonString / jsonStringOrNull', () {
    test('null 与空串', () {
      expect(jsonString(null), '');
      expect(jsonString(null, 'static'), 'static');
      expect(jsonString(42), '42');
      expect(jsonStringOrNull(null), isNull);
      expect(jsonStringOrNull(''), isNull);
      expect(jsonStringOrNull('a'), 'a');
    });
  });

  group('jsonStringList / asStringList', () {
    test('jsonStringList 保留空串，跳过 null', () {
      expect(jsonStringList(['PATH=/bin', '', null, 'HOME=/root']), [
        'PATH=/bin',
        '',
        'HOME=/root',
      ]);
    });

    test('asStringList 丢掉空串，避免 Docker Entrypoint [""] 污染启动命令', () {
      expect(asStringList(['', 'nginx', null, '']), ['nginx']);
      expect(asStringList(null), isEmpty);
    });
  });

  group('jsonMap / jsonList', () {
    test('容忍 Map<dynamic, dynamic> 与非对象元素', () {
      expect(jsonMap(null), isEmpty);
      expect(jsonMapOrNull(null), isNull);
      expect(jsonMap({1: 'a'}), {'1': 'a'});
      expect(
        jsonList([
          {'id': 1},
          'skip',
          {2: 3},
        ], (m) => m).length,
        2,
      );
    });
  });

  group('jsonTime', () {
    test('Go 零值与空串视为 null，RFC3339 转为本地时间', () {
      expect(jsonTime(null), isNull);
      expect(jsonTime(''), isNull);
      expect(jsonTime('0001-01-01T00:00:00Z'), isNull);
      final parsed = jsonTime('2026-07-26T18:13:00+08:00');
      expect(parsed, isNotNull);
      expect(parsed!.isUtc, isFalse);
      expect(
        jsonTime(1700000000),
        DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000).toLocal(),
      );
    });
  });
}
