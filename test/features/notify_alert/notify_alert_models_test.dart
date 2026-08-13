import 'package:acepocket/features/notify_alert/models/notify_setting.dart';
import 'package:acepocket/features/notify_alert/models/paged.dart';
import 'package:acepocket/features/notify_alert/models/webhook.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NotifySetting 值相等（事件通知草稿的「是否有未保存修改」判定）', () {
    test('内容相同顺序不同视为相等', () {
      const a = NotifySetting(
        events: <String>['backup', 'login'],
        channels: <int>[2, 1],
      );
      const b = NotifySetting(
        events: <String>['login', 'backup'],
        channels: <int>[1, 2],
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('勾选后再取消回到原样不算修改', () {
      const saved = NotifySetting(
        events: <String>['backup'],
        channels: <int>[1],
      );
      final draft = saved
          .copyWith(events: <String>['backup', 'login'])
          .copyWith(events: <String>['backup']);
      expect(draft, equals(saved));
    });

    test('多一个事件即视为有修改', () {
      const saved = NotifySetting(
        events: <String>['backup'],
        channels: <int>[1],
      );
      final draft = saved.copyWith(events: <String>['backup', 'login']);
      expect(draft == saved, isFalse);
    });
  });

  group('parsePagedResult', () {
    test('解析 total 与 items', () {
      final result = parsePagedResult(<String, dynamic>{
        'total': 3,
        'items': <dynamic>[
          <String, dynamic>{'id': 1, 'name': 'a', 'key': 'k1'},
          <String, dynamic>{'id': 2, 'name': 'b', 'key': 'k2'},
        ],
      }, WebHook.fromJson);
      expect(result.total, 3);
      expect(result.items.map((e) => e.id), <int>[1, 2]);
    });

    test('null / 非法结构返回空列表而不是抛异常', () {
      final result = parsePagedResult(null, WebHook.fromJson);
      expect(result.total, 0);
      expect(result.items, isEmpty);

      final noItems = parsePagedResult(<String, dynamic>{
        'items': 'oops',
      }, WebHook.fromJson);
      expect(noItems.total, 0);
      expect(noItems.items, isEmpty);
    });
  });
}
