import 'package:acepocket/features/cron_backup/widgets/kv_editor.dart';
import 'package:acepocket/features/cron_backup/widgets/string_list_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 把编辑器挂进一个持有列表状态的宿主页面，模拟计划任务编辑页的用法：
/// 子组件 onChanged 回传新列表 → 父级 setState → 子组件用新列表重建。
class _StringHost extends StatefulWidget {
  const _StringHost({required this.initial});

  final List<String> initial;

  @override
  State<_StringHost> createState() => _StringHostState();
}

class _StringHostState extends State<_StringHost> {
  late List<String> values = List.of(widget.initial);

  /// 供测试模拟「外部整体替换列表」（如切换备份类型后清空目标）。
  void replaceValues(List<String> next) => setState(() => values = next);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: StringListEditor(
            label: '备份目录',
            values: values,
            addLabel: '添加目录',
            onChanged: (v) => setState(() => values = v),
          ),
        ),
      ),
    );
  }
}

class _KvHost extends StatefulWidget {
  const _KvHost({required this.initial});

  final List<KvEntry> initial;

  @override
  State<_KvHost> createState() => _KvHostState();
}

class _KvHostState extends State<_KvHost> {
  late List<KvEntry> entries = List.of(widget.initial);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: KvEditor(
            label: '自定义请求头',
            entries: entries,
            onChanged: (v) => setState(() => entries = v),
          ),
        ),
      ),
    );
  }
}

/// 按顺序取出所有输入框当前展示的文字。
List<String> _fieldTexts(WidgetTester tester) => tester
    .widgetList<TextField>(find.byType(TextField))
    .map((f) => f.controller?.text ?? '')
    .toList();

void main() {
  group('StringListEditor 删除后显示与数据一致', () {
    testWidgets('删除首行', (tester) async {
      await tester.pumpWidget(const _StringHost(initial: ['/a', '/b', '/c']));
      await tester.tap(find.byIcon(Icons.remove_circle_outline).first);
      await tester.pump();
      expect(_fieldTexts(tester), ['/b', '/c']);
      final host = tester.state<_StringHostState>(find.byType(_StringHost));
      expect(host.values, ['/b', '/c']);
    });

    testWidgets('删除中间行', (tester) async {
      await tester.pumpWidget(const _StringHost(initial: ['/a', '/b', '/c']));
      await tester.tap(find.byIcon(Icons.remove_circle_outline).at(1));
      await tester.pump();
      expect(_fieldTexts(tester), ['/a', '/c']);
    });

    testWidgets('删除末行', (tester) async {
      await tester.pumpWidget(const _StringHost(initial: ['/a', '/b', '/c']));
      await tester.tap(find.byIcon(Icons.remove_circle_outline).at(2));
      await tester.pump();
      expect(_fieldTexts(tester), ['/a', '/b']);
    });

    testWidgets('连续删除两行', (tester) async {
      await tester.pumpWidget(
        const _StringHost(initial: ['/a', '/b', '/c', '/d']),
      );
      await tester.tap(find.byIcon(Icons.remove_circle_outline).first);
      await tester.pump();
      await tester.tap(find.byIcon(Icons.remove_circle_outline).first);
      await tester.pump();
      expect(_fieldTexts(tester), ['/c', '/d']);
      final host = tester.state<_StringHostState>(find.byType(_StringHost));
      expect(host.values, ['/c', '/d']);
    });

    testWidgets('新增一行后编辑并删除，剩余行内容不串位', (tester) async {
      await tester.pumpWidget(const _StringHost(initial: ['/a']));
      await tester.tap(find.text('添加目录'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(1), '/b');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.remove_circle_outline).first);
      await tester.pump();
      expect(_fieldTexts(tester), ['/b']);
      final host = tester.state<_StringHostState>(find.byType(_StringHost));
      expect(host.values, ['/b']);
    });

    testWidgets('外部整体替换列表时输入框跟着换', (tester) async {
      await tester.pumpWidget(const _StringHost(initial: ['/a', '/b']));
      final host = tester.state<_StringHostState>(find.byType(_StringHost));
      host.replaceValues(['/x']);
      await tester.pump();
      expect(_fieldTexts(tester), ['/x']);
    });
  });

  group('KvEditor 删除后显示与数据一致', () {
    List<KvEntry> seed() => [
      KvEntry(key: 'A', value: '1'),
      KvEntry(key: 'B', value: '2'),
      KvEntry(key: 'C', value: '3'),
    ];

    testWidgets('删除首行', (tester) async {
      await tester.pumpWidget(_KvHost(initial: seed()));
      await tester.tap(find.byIcon(Icons.remove_circle_outline).first);
      await tester.pump();
      expect(_fieldTexts(tester), ['B', '2', 'C', '3']);
    });

    testWidgets('删除中间行', (tester) async {
      await tester.pumpWidget(_KvHost(initial: seed()));
      await tester.tap(find.byIcon(Icons.remove_circle_outline).at(1));
      await tester.pump();
      expect(_fieldTexts(tester), ['A', '1', 'C', '3']);
      final host = tester.state<_KvHostState>(find.byType(_KvHost));
      expect(host.entries.map((e) => e.key).toList(), ['A', 'C']);
      expect(host.entries.map((e) => e.value).toList(), ['1', '3']);
    });

    testWidgets('删除末行', (tester) async {
      await tester.pumpWidget(_KvHost(initial: seed()));
      await tester.tap(find.byIcon(Icons.remove_circle_outline).at(2));
      await tester.pump();
      expect(_fieldTexts(tester), ['A', '1', 'B', '2']);
    });

    testWidgets('连续删除两行', (tester) async {
      await tester.pumpWidget(_KvHost(initial: seed()));
      await tester.tap(find.byIcon(Icons.remove_circle_outline).first);
      await tester.pump();
      await tester.tap(find.byIcon(Icons.remove_circle_outline).first);
      await tester.pump();
      expect(_fieldTexts(tester), ['C', '3']);
      final host = tester.state<_KvHostState>(find.byType(_KvHost));
      expect(host.entries.map((e) => e.key).toList(), ['C']);
    });
  });
}
