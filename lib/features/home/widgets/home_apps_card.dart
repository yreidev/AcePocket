import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/widgets/section_card.dart';
import '../providers/home_providers.dart';
import 'info_row.dart';

/// 首页展示应用（`GET /home/apps`）：面板中标记为「首页显示」的已安装应用。
class HomeAppsCard extends ConsumerWidget {
  const HomeAppsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(homeAppsProvider);

    // 未配置首页应用时不占位。
    if (async.value != null && async.value!.isEmpty) {
      return const SizedBox.shrink();
    }

    return SectionCard(
      title: '已安装应用',
      child: async.when(
        loading: () => const SizedBox(
          height: 48,
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        error: (error, _) => InlineError(
          message: describeError(error),
          onRetry: () => ref.invalidate(homeAppsProvider),
        ),
        data: (apps) => Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final app in apps)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                // Row 的非弹性子项按无限宽度布局，应用名或版本号一长就会
                // 冲出 Wrap 的行宽（面板允许自定义应用名）。用 Flexible
                // 让它们在拥挤时省略号收尾。
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        app.name.isEmpty ? app.slug : app.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    if (app.version.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          app.version,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
