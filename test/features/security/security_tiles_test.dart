import 'package:acepocket/features/security/widgets/security_tiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 「未保存」角标的回归测试。
///
/// 面板安全 / 防篡改 / 扫描感知三处都是「草稿 + 显式保存」：点一下配置行，
/// 行上立刻显示新值但其实只改了本地草稿。历史上这里没有任何视觉区分，
/// 用户会以为安全入口 / 端口已经改好，返回后静默丢失。
/// 下面两条用例锁死「dirty 为 true 必须出现未保存角标」这个契约。
Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: ListView(children: [child])),
);

void main() {
  group('SettingValueTile 未保存标记', () {
    testWidgets('dirty 为 true 时展示「未保存」角标', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SettingValueTile(title: '面板端口', value: '8888', dirty: true),
        ),
      );

      expect(find.text('未保存'), findsOneWidget);
      expect(find.text('8888'), findsOneWidget);
    });

    testWidgets('dirty 为 false 时不展示角标', (tester) async {
      await tester.pumpWidget(
        _wrap(const SettingValueTile(title: '面板端口', value: '8888')),
      );

      expect(find.text('未保存'), findsNothing);
    });

    testWidgets('未保存的值以 tertiary 色区分于已生效的值', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const Column(
            children: [
              SettingValueTile(title: '安全入口', value: '/a', dirty: true),
              SettingValueTile(title: '登录超时', value: '120 分钟'),
            ],
          ),
        ),
      );

      final context = tester.element(find.byType(Scaffold));
      final scheme = Theme.of(context).colorScheme;
      final dirtyText = tester.widget<Text>(find.text('/a'));
      final cleanText = tester.widget<Text>(find.text('120 分钟'));
      expect(dirtyText.style?.color, scheme.tertiary);
      expect(cleanText.style?.color, isNot(scheme.tertiary));
    });
  });

  group('SettingSwitchTile 未保存标记', () {
    testWidgets('dirty 为 true 时展示「未保存」角标', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SettingSwitchTile(
            title: '登录验证码',
            value: true,
            dirty: true,
            onChanged: (_) {},
          ),
        ),
      );

      expect(find.text('未保存'), findsOneWidget);
    });

    testWidgets('dirty 为 false 时不展示角标', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SettingSwitchTile(title: '登录验证码', value: true, onChanged: (_) {}),
        ),
      );

      expect(find.text('未保存'), findsNothing);
    });

    testWidgets('开关带语义标签，读屏能念出它控制的是哪一项', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _wrap(
          SettingSwitchTile(title: '允许 Ping', value: true, onChanged: (_) {}),
        ),
      );

      expect(find.bySemanticsLabel(RegExp('允许 Ping')), findsWidgets);
      handle.dispose();
    });
  });
}
