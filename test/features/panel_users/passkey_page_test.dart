import 'package:acepocket/core/api/api_exception.dart';
import 'package:acepocket/core/version/panel_version_provider.dart';
import 'package:acepocket/features/panel_users/pages/passkey_page.dart';
import 'package:acepocket/features/panel_users/providers/panel_user_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 面板不可达时三张卡片都会落到错误态。历史实现把 ErrorView 塞进
/// `SizedBox(height: 140/160)`：图标 48 + 间距 + 文案 + 「重试」按钮至少要 200dp，
/// 结果错误原因被裁掉、重试按钮完全不可见也点不到。
/// 本用例在 360×640 的小屏上渲染错误态：一旦再出现固定高度，
/// RenderFlex 溢出会让测试直接失败。
void main() {
  const error = ApiException('无法连接面板：连接 192.0.2.1:8888 超时');

  Widget buildPage() {
    return ProviderScope(
      overrides: [
        // 版本探测不参与本用例，直接给 null（= 功能按可用处理）。
        panelVersionProvider.overrideWith((ref) async => null),
        passkeyStatusProvider.overrideWith((ref) async => throw error),
        panelUserOptionsProvider.overrideWith((ref) async => throw error),
        currentPanelUserProvider.overrideWith((ref) async => throw error),
      ],
      child: const MaterialApp(home: PasskeyPage()),
    );
  }

  testWidgets('通行密钥页加载失败时错误原因与重试按钮完整可见', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    // 错误原因（面板返回的 msg）能读到，不是只剩一个红色感叹号。
    expect(find.textContaining('无法连接面板'), findsWidgets);

    // 「重试」按钮真实可见且可命中：hitTestable 会排除被裁掉 / 被遮挡的按钮。
    expect(find.widgetWithText(FilledButton, '重试').hitTestable(), findsWidgets);

    // 滚到底再检查一次，确保下方卡片的错误态同样没有溢出。
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.textContaining('无法连接面板'), findsWidgets);
  });
}
