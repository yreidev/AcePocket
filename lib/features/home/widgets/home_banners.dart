import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/animated_reveal.dart';
import '../models/panel_models.dart';
import '../providers/home_providers.dart';
import 'formatters.dart';

/// 面板健康问题横幅（无问题时不占位）。
class HealthBanner extends ConsumerWidget {
  const HealthBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final issues = ref.watch(healthProvider).value ?? const <HealthIssue>[];
    // 健康检查是轮询回来的，直接 if/else 会让横幅在首页上突然弹出、把下方
    // 卡片整体顶下去；交给 AnimatedReveal 展开。
    return AnimatedReveal(
      visible: issues.isNotEmpty,
      child: issues.isEmpty
          ? const SizedBox.shrink()
          : _buildBanner(context, issues),
    );
  }

  Widget _buildBanner(BuildContext context, List<HealthIssue> issues) {
    final theme = Theme.of(context);
    final hasError = issues.any((i) => i.isError);
    final background = hasError
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.tertiaryContainer;
    final foreground = hasError
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onTertiaryContainer;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                hasError ? Icons.error_outline : Icons.warning_amber_rounded,
                size: 18,
                color: foreground,
              ),
              const SizedBox(width: 8),
              Text(
                '面板检测到 ${issues.length} 个问题',
                style: theme.textTheme.titleSmall?.copyWith(color: foreground),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final issue in issues)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '· [${issue.key}] ${issue.message}'
                '${issue.since == null ? '' : '（${formatDateTime(issue.since)}）'}',
                style: theme.textTheme.bodySmall?.copyWith(color: foreground),
              ),
            ),
        ],
      ),
    );
  }
}

/// 面板新版本提示横幅，点击进入升级页（`/panel/update`）。
class PanelUpdateBanner extends ConsumerWidget {
  const PanelUpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasUpdate = ref.watch(panelUpdateProvider).value ?? false;
    return AnimatedReveal(
      visible: hasUpdate,
      child: hasUpdate ? _buildBanner(context) : const SizedBox.shrink(),
    );
  }

  Widget _buildBanner(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/panel/update'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  Icons.system_update_alt_rounded,
                  size: 18,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '面板有新版本可用，点击查看更新日志并升级',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
