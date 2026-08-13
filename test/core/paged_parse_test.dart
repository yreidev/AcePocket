import 'package:acepocket/core/models/paged.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> item(Map<String, dynamic> json) => json;

  test('标准 {total, items} 载荷', () {
    final paged = Paged.fromJson({
      'total': 3,
      'items': [
        {'id': 1},
        {'id': 2},
      ],
    }, item);
    expect(paged.total, 3);
    expect(paged.items, [
      {'id': 1},
      {'id': 2},
    ]);
  });

  test('data 直接是数组时以长度为 total', () {
    final paged = Paged.parse([
      {'id': 1},
      {'id': 2},
    ], item);
    expect(paged.total, 2);
    expect(paged.items.length, 2);
  });

  test('Go 空切片 items=null、Map 类型漂移', () {
    final paged = Paged.fromJson({
      'total': '4',
      'items': [
        {'id': 1},
        null,
        <dynamic, dynamic>{'id': 2},
      ],
    }, item);
    expect(paged.total, 4);
    expect(paged.items.length, 2);
  });

  test('非法结构返回空页', () {
    expect(Paged.fromJson(null, item).isEmpty, isTrue);
    expect(Paged.fromJson('nope', item).total, 0);
  });

  test('parsePagedResult 产出 Notifier 使用的 PagedResult', () {
    final result = parsePagedResult({
      'total': 1,
      'items': [
        {'id': 9},
      ],
    }, item);
    expect(result.total, 1);
    expect(result.items.single, {'id': 9});
  });
}
