import 'package:acepocket/core/theme/motion.dart';
import 'package:acepocket/core/theme/theme.dart';
import 'package:acepocket/core/widgets/animated_reveal.dart';
import 'package:acepocket/core/widgets/fade_switch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android 页面转场固定为预测性返回', () {
    // 依赖 Flutter 默认值会在升级 SDK 时被悄悄换掉（近几个大版本换过三次），
    // 这里锁死：配合 AndroidManifest 的 enableOnBackInvokedCallback，
    // 返回手势才会跟手预览目的页。
    for (final theme in <ThemeData>[AppTheme.light, AppTheme.dark]) {
      expect(
        theme.pageTransitionsTheme.builders[TargetPlatform.android],
        isA<PredictiveBackPageTransitionsBuilder>(),
      );
    }
  });

  testWidgets('系统开启「移除动画」时自定义动效时长归零', (tester) async {
    late Duration normal;
    late Duration reduced;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            normal = AppMotion.resolve(context, AppMotion.stateSwap);
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: Builder(
                builder: (context) {
                  reduced = AppMotion.resolve(context, AppMotion.stateSwap);
                  return const SizedBox.shrink();
                },
              ),
            );
          },
        ),
      ),
    );

    expect(normal, AppMotion.stateSwap);
    expect(reduced, Duration.zero);
  });

  group('FadeSwitch', () {
    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('首帧直接展示内容，不做入场过渡', (tester) async {
      await tester.pumpWidget(
        wrap(const FadeSwitch(child: Text('内容', key: ValueKey<String>('a')))),
      );
      expect(find.text('内容'), findsOneWidget);
      // 首帧就是稳定态：没有待完成的动画。
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('淡出中的旧内容仍在树上，但不再响应点击', (tester) async {
      var oldTaps = 0;

      Widget build({required bool second}) => wrap(
        FadeSwitch(
          child: second
              ? const SizedBox(key: ValueKey<String>('b'), width: 1, height: 1)
              : GestureDetector(
                  key: const ValueKey<String>('a'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => oldTaps++,
                  child: const SizedBox(width: 200, height: 200),
                ),
        ),
      );

      await tester.pumpWidget(build(second: false));
      final corner =
          tester.getTopLeft(find.byKey(const ValueKey<String>('a'))) +
          const Offset(8, 8);
      await tester.tapAt(corner);
      expect(oldTaps, 1);

      await tester.pumpWidget(build(second: true));
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byKey(const ValueKey<String>('a')), findsOneWidget);

      // 切服务器时列表正在淡出，此刻点中旧条目会跳到上一台机器的资源。
      await tester.tapAt(corner);
      expect(oldTaps, 1);

      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('a')), findsNothing);
    });
  });

  group('AnimatedReveal', () {
    Widget build({required bool visible}) => MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: AnimatedReveal(
            visible: visible,
            child: const SizedBox(width: double.infinity, height: 80),
          ),
        ),
      ),
    );

    testWidgets('隐藏时不占高度，展开后撑开到内容高度', (tester) async {
      await tester.pumpWidget(build(visible: false));
      expect(tester.getSize(find.byType(AnimatedReveal)).height, 0);

      await tester.pumpWidget(build(visible: true));
      // 过渡中高度介于两者之间，说明是展开而不是瞬间顶开下方内容。
      await tester.pump(const Duration(milliseconds: 60));
      final mid = tester.getSize(find.byType(AnimatedReveal)).height;
      expect(mid, greaterThan(0));
      expect(mid, lessThan(80));

      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(AnimatedReveal)).height, 80);
    });
  });
}
