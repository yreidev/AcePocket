import 'dart:convert';

import 'package:acepocket/core/usage/more_usage_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 快速构造一条使用记录（测试辅助）。
MoreUsageRecord _rec(String path, int count, int lastUsedMs) =>
    MoreUsageRecord(path: path, count: count, lastUsedMs: lastUsedMs);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    MoreUsageStore.instance.resetForTesting();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('topUsagePaths 排序', () {
    test('count 降序排序正确', () {
      final records = <String, MoreUsageRecord>{
        '/a': _rec('/a', 1, 100),
        '/b': _rec('/b', 5, 100),
        '/c': _rec('/c', 3, 100),
        '/d': _rec('/d', 9, 100),
      };
      expect(topUsagePaths(records), <String>['/d', '/b', '/c', '/a']);
    });

    test('count 相同按 lastUsedMs 降序', () {
      final records = <String, MoreUsageRecord>{
        '/a': _rec('/a', 2, 100),
        '/b': _rec('/b', 2, 300),
        '/c': _rec('/c', 2, 200),
        '/d': _rec('/d', 2, 400),
      };
      expect(topUsagePaths(records), <String>['/d', '/b', '/c', '/a']);
    });

    test('count 与 lastUsedMs 都相同按 path 升序', () {
      final records = <String, MoreUsageRecord>{
        '/firewall': _rec('/firewall', 2, 100),
        '/apps': _rec('/apps', 2, 100),
        '/websites': _rec('/websites', 2, 100),
        '/databases': _rec('/databases', 2, 100),
      };
      expect(topUsagePaths(records), <String>[
        '/apps',
        '/databases',
        '/firewall',
        '/websites',
      ]);
    });

    test('count == 0 的记录不参与统计', () {
      final records = <String, MoreUsageRecord>{
        '/a': _rec('/a', 0, 900),
        '/b': _rec('/b', 1, 100),
        '/c': _rec('/c', 1, 200),
        '/d': _rec('/d', 1, 300),
        '/e': _rec('/e', 1, 400),
      };
      expect(topUsagePaths(records), <String>['/e', '/d', '/c', '/b']);
    });

    test('恰好 3 条 count>0 返回空列表', () {
      final records = <String, MoreUsageRecord>{
        '/a': _rec('/a', 3, 100),
        '/b': _rec('/b', 2, 100),
        '/c': _rec('/c', 1, 100),
      };
      expect(topUsagePaths(records), isEmpty);
    });

    test('恰好 4 条 count>0 返回 4 条', () {
      final records = <String, MoreUsageRecord>{
        '/a': _rec('/a', 4, 100),
        '/b': _rec('/b', 3, 100),
        '/c': _rec('/c', 2, 100),
        '/d': _rec('/d', 1, 100),
      };
      expect(topUsagePaths(records), <String>['/a', '/b', '/c', '/d']);
    });

    test('10 条只取前 8', () {
      final records = <String, MoreUsageRecord>{
        for (var i = 1; i <= 10; i++) '/p$i': _rec('/p$i', i, 100),
      };
      expect(topUsagePaths(records), <String>[
        '/p10',
        '/p9',
        '/p8',
        '/p7',
        '/p6',
        '/p5',
        '/p4',
        '/p3',
      ]);
    });

    test('空 map 返回空列表', () {
      expect(topUsagePaths(<String, MoreUsageRecord>{}), isEmpty);
    });
  });

  group('MoreUsageStore', () {
    test('recordTap 两次后 count == 2 且写入 storageKey', () async {
      await MoreUsageStore.instance.init();
      MoreUsageStore.instance.nowMsForTesting = () => 1700000000000;
      await MoreUsageStore.instance.recordTap('/websites');
      await MoreUsageStore.instance.recordTap('/websites');

      final record = MoreUsageStore.instance.records['/websites'];
      expect(record, isNotNull);
      expect(record!.count, 2);
      expect(record.lastUsedMs, 1700000000000);

      // 从 SharedPreferences 读回 JSON 验证持久化内容。
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(MoreUsageStore.storageKey);
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      expect(decoded['/websites'], <String, int>{'c': 2, 't': 1700000000000});
    });

    test('resetForTesting + init 能读回持久化数据（往返一致）', () async {
      await MoreUsageStore.instance.init();
      MoreUsageStore.instance.nowMsForTesting = () => 1700000000000;
      await MoreUsageStore.instance.recordTap('/websites');
      await MoreUsageStore.instance.recordTap('/firewall');
      await MoreUsageStore.instance.recordTap('/firewall');

      MoreUsageStore.instance.resetForTesting();
      expect(MoreUsageStore.instance.records, isEmpty);

      await MoreUsageStore.instance.init();
      final records = MoreUsageStore.instance.records;
      expect(records, hasLength(2));
      expect(records['/websites']!.count, 1);
      expect(records['/websites']!.lastUsedMs, 1700000000000);
      expect(records['/firewall']!.count, 2);
      expect(records['/firewall']!.lastUsedMs, 1700000000000);
    });

    test('预置整体损坏 JSON 时 init 不抛且 records 为空', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        MoreUsageStore.storageKey: 'not-json',
      });
      await MoreUsageStore.instance.init();
      expect(MoreUsageStore.instance.records, isEmpty);
    });

    test('预置坏条目时 init 不抛且忽略坏条目、保留好条目', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        MoreUsageStore.storageKey:
            '{"/a": 1, "/b": {"c": "x", "t": 2}, "/c": {"c": -1, "t": 2}, '
            '"/websites": {"c": 3, "t": 1700000000000}}',
      });
      await MoreUsageStore.instance.init();
      final records = MoreUsageStore.instance.records;
      expect(records.keys, <String>['/websites']);
      expect(records['/websites']!.count, 3);
      expect(records['/websites']!.lastUsedMs, 1700000000000);
    });

    test('clear 后 records 为空且存储键被移除', () async {
      await MoreUsageStore.instance.init();
      await MoreUsageStore.instance.recordTap('/websites');
      await MoreUsageStore.instance.clear();

      expect(MoreUsageStore.instance.records, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(MoreUsageStore.storageKey), isFalse);
    });

    test('records 返回不可变快照', () async {
      await MoreUsageStore.instance.init();
      await MoreUsageStore.instance.recordTap('/websites');
      expect(
        () => MoreUsageStore.instance.records.remove('/websites'),
        throwsUnsupportedError,
      );
    });
  });
}
