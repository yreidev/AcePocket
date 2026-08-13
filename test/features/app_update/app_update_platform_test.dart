import 'dart:io';

import 'package:acepocket/features/app_update/models/app_update_models.dart';
import 'package:acepocket/features/app_update/widgets/update_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('非 Android 平台不会打开 APK 更新对话框', (tester) async {
    if (Platform.isAndroid) return;

    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (builderContext) {
            context = builderContext;
            return const SizedBox();
          },
        ),
      ),
    );

    await showAppUpdateDialog(
      context,
      const AppRelease(
        tagName: 'v9.9.9',
        body: '测试更新',
        publishedAt: null,
        assets: [],
      ),
    );
    await tester.pump();

    expect(find.text('发现新版本 v9.9.9'), findsNothing);
  });
}
