import 'package:acepocket/core/pages/more_page.dart';
import 'package:acepocket/core/pages/more_page_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('filterMoreEntries', () {
    test('中文子串命中且分组标题正确', () {
      final results = filterMoreEntries(kMoreGroups, '防火');
      expect(results, hasLength(1));
      expect(results.single.entry.label, '防火墙');
      expect(results.single.groupTitle, '安全');
    });

    test('拉丁子串大小写不敏感', () {
      // 小写 'ssl' 应命中大写 label 'SSL 证书'（以及 'SSL' 开头的其他入口）。
      final lower = filterMoreEntries(kMoreGroups, 'ssl');
      expect(lower.map((r) => r.entry.label), contains('SSL 证书'));

      // 大写 query 同样命中。
      final upper = filterMoreEntries(kMoreGroups, 'SSL');
      expect(
        upper.map((r) => r.entry.label).toList(),
        lower.map((r) => r.entry.label).toList(),
      );
    });

    test('拼音首字母命中', () {
      final results = filterMoreEntries(kMoreGroups, 'fhq');
      expect(results.map((r) => r.entry.label), contains('防火墙'));
    });

    test('拼音全拼命中', () {
      final results = filterMoreEntries(kMoreGroups, 'fanghuoqiang');
      expect(results, hasLength(1));
      expect(results.single.entry.label, '防火墙');
    });

    test('空串与纯空白返回空列表', () {
      expect(filterMoreEntries(kMoreGroups, ''), isEmpty);
      expect(filterMoreEntries(kMoreGroups, '   '), isEmpty);
      expect(filterMoreEntries(kMoreGroups, '\t\n'), isEmpty);
    });

    test('带前后空格的 query 正常 trim', () {
      final results = filterMoreEntries(kMoreGroups, '  防火墙  ');
      expect(results, hasLength(1));
      expect(results.single.entry.label, '防火墙');
    });

    test('无匹配返回空列表', () {
      expect(filterMoreEntries(kMoreGroups, '不存在的功能xyz'), isEmpty);
    });

    test('多分组命中时保持 kMoreGroups 原始顺序', () {
      // '面板' 命中多个分组的入口：面板日志（运维与监控）、面板迁移（工具箱）、
      // 面板安全（安全）、面板设置等（系统），应按原始遍历顺序排列。
      final labels = filterMoreEntries(
        kMoreGroups,
        '面板',
      ).map((r) => r.entry.label).toList();
      expect(labels, ['面板日志', '面板迁移', '面板安全', '面板设置', '面板用户', '面板证书', '面板升级']);
    });

    test('结果携带正确的分组标题', () {
      final results = filterMoreEntries(kMoreGroups, 'api');
      expect(results, hasLength(1));
      expect(results.single.entry.label, 'API 令牌');
      expect(results.single.groupTitle, '系统');
    });
  });

  group('kMoreEntryPinyin', () {
    test('覆盖 kMoreGroups 全部 label', () {
      for (final group in kMoreGroups) {
        for (final entry in group.entries) {
          expect(
            kMoreEntryPinyin.containsKey(entry.label),
            isTrue,
            reason: 'kMoreEntryPinyin 缺少入口「${entry.label}」的检索串',
          );
          expect(
            kMoreEntryPinyin[entry.label],
            isNotEmpty,
            reason: '入口「${entry.label}」的检索串列表为空',
          );
        }
      }
    });

    test('检索串均为小写且不含空白', () {
      for (final candidates in kMoreEntryPinyin.values) {
        for (final candidate in candidates) {
          expect(candidate, candidate.toLowerCase());
          expect(candidate.contains(RegExp(r'\s')), isFalse);
        }
      }
    });
  });
}
