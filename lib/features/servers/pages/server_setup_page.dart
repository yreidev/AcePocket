import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/storage/server_store.dart';
import '../providers/servers_providers.dart';
import '../widgets/server_form.dart';

/// 初次配置引导页：未配置任何服务器时的落地页（路由守卫会重定向到此）。
///
/// 填写服务器信息，保存前自动执行连接测试并展示结果；保存成功后该服务器
/// 自动成为当前选中服务器（`serverListProvider.add` 的行为），随后进入主界面。
class ServerSetupPage extends ConsumerWidget {
  const ServerSetupPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasServers = ref.watch(hasServersProvider);

    return Scaffold(
      // 已有服务器时（从列表页等入口进入）展示 AppBar 以便返回。
      appBar: hasServers
          ? AppBar(
              title: const Text('添加服务器'),
              actions: [
                TextButton(
                  onPressed: () => context.go('/servers'),
                  child: const Text('服务器列表'),
                ),
              ],
            )
          : null,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          children: [
            if (!hasServers) ...[
              const SizedBox(height: 16),
              Icon(Icons.dns_outlined, size: 64, color: colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                '欢迎使用 AcePanel',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                '添加你的第一台服务器以开始管理',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              const _GuideCard(),
              const SizedBox(height: 24),
            ],
            ServerForm(
              submitLabel: '保存并进入',
              onSubmit: (config) async {
                final notifier = ref.read(serverListProvider.notifier);
                await notifier.add(config);
                // 保险起见：确保新服务器成为当前选中项。
                if (ref.read(activeServerProvider) == null) {
                  await ref
                      .read(activeServerProvider.notifier)
                      .select(config.id);
                }
                if (!context.mounted) return;
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(content: Text('已添加「${config.name}」')),
                  );
                context.go('/');
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 「如何获取 API 令牌」的图文引导。
class _GuideCard extends StatelessWidget {
  const _GuideCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // 序号圆点随系统字号放大，否则 200% 字号下数字会被 18dp 圆圈裁掉。
    final circleSize = MediaQuery.textScalerOf(
      context,
    ).scale(18).clamp(18.0, 32.0);

    const steps = <String>[
      '在浏览器登录你的 AcePanel 面板',
      '进入「设置 - API 令牌」，创建一个新令牌',
      '复制令牌 ID 与令牌值（令牌值仅在创建时可见）',
      '在下方填入面板地址与令牌信息并保存',
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.help_outline, size: 18, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                '如何获取 API 令牌',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: circleSize,
                    height: circleSize,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      steps[i],
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
