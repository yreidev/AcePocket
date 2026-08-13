import 'package:acepocket/features/terminal/widgets/terminal_keyboard_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

Widget _wrap(Widget child, {TextScaler textScaler = TextScaler.noScaling}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: textScaler),
      child: Scaffold(body: Column(children: [const Spacer(), child])),
    ),
  );
}

TerminalKeyboardBar _bar({
  bool enabled = true,
  void Function(TerminalKey key)? onKey,
  void Function(String text)? onText,
  void Function(String letter)? onCtrl,
}) {
  return TerminalKeyboardBar(
    enabled: enabled,
    onKey: onKey ?? (_) {},
    onText: onText ?? (_) {},
    onCtrl: onCtrl ?? (_) {},
  );
}

void main() {
  testWidgets('键帽触摸目标不小于 48×48dp', (tester) async {
    await tester.pumpWidget(_wrap(_bar()));

    final escSize = tester.getSize(
      find.ancestor(of: find.text('Esc'), matching: find.byType(InkWell)),
    );
    expect(escSize.height, greaterThanOrEqualTo(48));
    expect(escSize.width, greaterThanOrEqualTo(48));
  });

  testWidgets('大字号下键帽随之长高，文字不被裁切', (tester) async {
    await tester.pumpWidget(
      _wrap(_bar(), textScaler: const TextScaler.linear(2)),
    );

    final size = tester.getSize(
      find.ancestor(of: find.text('Home'), matching: find.byType(InkWell)),
    );
    expect(size.height, greaterThan(48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('纯图标的方向键带读屏名称', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_wrap(_bar()));

    for (final label in const [
      '方向键 上（上一条历史命令）',
      '方向键 下（下一条历史命令）',
      '方向键 左（光标左移）',
      '方向键 右（光标右移）',
    ]) {
      expect(
        find.bySemanticsLabel(label),
        findsOneWidget,
        reason: '$label 缺少语义名称，TalkBack 只会念「按钮」',
      );
    }

    handle.dispose();
  });

  testWidgets('点击键帽回调对应按键；未连接时禁用', (tester) async {
    final keys = <TerminalKey>[];
    final texts = <String>[];
    await tester.pumpWidget(_wrap(_bar(onKey: keys.add, onText: texts.add)));

    await tester.tap(find.text('Esc'));
    await tester.tap(find.text('Tab'));
    expect(keys, [TerminalKey.escape, TerminalKey.tab]);

    // 符号键在横向列表的可视区之外，先滚动过去。
    await tester.scrollUntilVisible(
      find.text('/'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('/'));
    expect(texts, ['/']);

    // 未连接：同一个键再点一次不应产生输入（列表滚动位置保持不变）。
    await tester.pumpWidget(
      _wrap(_bar(enabled: false, onKey: keys.add, onText: texts.add)),
    );
    await tester.tap(find.text('/'));
    expect(texts, ['/']);
  });
}
