import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/format.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/section_card.dart';
import '../models/migration_status.dart';
import '../providers/migration_providers.dart';
import '../widgets/log_console.dart';
import '../widgets/migration_result_list.dart';

/// 迁移结果查看页 `/migration/results`。
///
/// 数据来自 `GET /toolbox_migration/results`（含全量日志）。
/// 面板的日志下载接口返回 `text/plain` 附件，App 端改为在日志面板内一键复制。
class MigrationResultsPage extends ConsumerWidget {
  const MigrationResultsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(migrationResultsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('迁移结果'),
        actions: [
          IconButton(
            // 读屏只念动词「刷新」分不清刷新什么，写明动作对象。
            tooltip: '刷新迁移结果',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(migrationResultsProvider),
          ),
        ],
      ),
      body: results.when(
        loading: () => const LoadingView(message: '正在读取迁移结果…'),
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(migrationResultsProvider),
        ),
        data: (snapshot) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(migrationResultsProvider);
            await ref.read(migrationResultsProvider.future);
          },
          child:
              snapshot.results.isEmpty &&
                  (snapshot.logs == null || snapshot.logs!.isEmpty)
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 120),
                    EmptyView(
                      message: '面板上没有迁移记录',
                      icon: Icons.swap_horiz_rounded,
                    ),
                  ],
                )
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(top: 6, bottom: 24),
                  children: [
                    _summaryCard(context, snapshot),
                    MigrationResultList(
                      results: snapshot.results,
                      title: '迁移结果',
                    ),
                    LogConsole(
                      logs: snapshot.logs ?? const <String>[],
                      height: 360,
                      running: snapshot.step == MigrationStep.running,
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _summaryCard(BuildContext context, MigrationSnapshot snapshot) {
    final theme = Theme.of(context);
    final success = snapshot.results
        .where((r) => r.status == MigrationItemStatus.success)
        .length;
    final failed = snapshot.results
        .where((r) => r.status == MigrationItemStatus.failed)
        .length;
    final skipped = snapshot.results
        .where((r) => r.status == MigrationItemStatus.skipped)
        .length;

    final start = snapshot.startedAt;
    final end = snapshot.endedAt;
    final elapsed = start == null
        ? ''
        : ' · 用时 ${formatDuration((end ?? DateTime.now()).difference(start))}';

    return SectionCard(
      title: '概览',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '当前状态：${snapshot.step.label}',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 6),
          Text(
            '成功 $success · 失败 $failed · 跳过 $skipped',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '开始 ${formatDateTime(start)}\n结束 ${formatDateTime(end)}$elapsed',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
