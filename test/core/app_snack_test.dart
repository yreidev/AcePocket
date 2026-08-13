import 'package:acepocket/core/api/api_exception.dart';
import 'package:acepocket/core/theme/theme.dart';
import 'package:acepocket/core/widgets/app_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 在指定主题下弹出提示，返回渲染出的 SnackBar 与文本样式。
Future<(SnackBar, TextStyle)> _showAndInspect(
  WidgetTester tester,
  ThemeData theme,
  void Function(BuildContext context) show,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => show(context),
            child: const Text('触发'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('触发'));
  await tester.pumpAndSettle();
  final snack = tester.widget<SnackBar>(find.byType(SnackBar));
  final text = tester.widget<Text>(
    find.descendant(of: find.byType(SnackBar), matching: find.byType(Text)),
  );
  return (snack, text.style!);
}

void main() {
  for (final (name, theme) in <(String, ThemeData)>[
    ('浅色', AppTheme.light),
    ('深色', AppTheme.dark),
  ]) {
    testWidgets('$name主题下错误提示用 errorContainer / onErrorContainer 配对', (
      tester,
    ) async {
      final scheme = theme.colorScheme;
      final (snack, style) = await _showAndInspect(
        tester,
        theme,
        (context) => showErrorSnack(context, const ApiException('磁盘空间不足')),
      );

      expect(find.text('磁盘空间不足'), findsOneWidget);
      expect(snack.backgroundColor, scheme.errorContainer);
      expect(style.color, scheme.onErrorContainer);
      // 错误提示可手动关闭，且停留时间长于默认值。
      expect(snack.showCloseIcon, isTrue);
      expect(snack.duration, const Duration(seconds: 6));
    });

    testWidgets('$name主题下成功 / 信息提示用 inverseSurface 配对', (tester) async {
      final scheme = theme.colorScheme;
      final (successSnack, successStyle) = await _showAndInspect(
        tester,
        theme,
        (context) => showSuccessSnack(context, '保存成功'),
      );
      expect(successSnack.backgroundColor, scheme.inverseSurface);
      expect(successStyle.color, scheme.onInverseSurface);

      final (infoSnack, infoStyle) = await _showAndInspect(
        tester,
        theme,
        (context) => showInfoSnack(context, '已复制到剪贴板'),
      );
      expect(infoSnack.backgroundColor, scheme.inverseSurface);
      expect(infoStyle.color, scheme.onInverseSurface);
    });
  }

  testWidgets('非 ApiException 的异常去掉英文类型前缀', (tester) async {
    await _showAndInspect(
      tester,
      AppTheme.light,
      // describeError 的正则是 `^\w+Exception:\s*`，命名异常会被剥掉前缀；
      // 裸 `Exception('x')`（前面无单词字符）不匹配，调用方应尽量抛具名异常。
      (context) => showErrorSnack(context, const FormatException('连接超时')),
    );
    expect(find.text('连接超时'), findsOneWidget);
  });
}
