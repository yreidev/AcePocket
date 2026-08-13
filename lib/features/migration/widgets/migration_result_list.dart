import 'package:flutter/material.dart';

import '../../../core/utils/format.dart';
import '../../../core/widgets/section_card.dart';
import '../models/migration_status.dart';

/// 迁移结果列表（进度页与结果页共用）。
class MigrationResultList extends StatelessWidget {
  const MigrationResultList({
    super.key,
    required this.results,
    this.title = '迁移项状态',
    this.emptyText = '暂无迁移项结果',
  });

  final List<MigrationItemResult> results;
  final String title;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SectionCard(
      title: '$title（${results.length}）',
      child: results.isEmpty
          ? Text(
              emptyText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < results.length; i++) ...[
                  if (i != 0) const Divider(height: 16),
                  MigrationResultTile(result: results[i]),
                ],
              ],
            ),
    );
  }
}

/// 单条迁移结果。
class MigrationResultTile extends StatelessWidget {
  const MigrationResultTile({super.key, required this.result});

  final MigrationItemResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final (IconData icon, Color color) = switch (result.status) {
      MigrationItemStatus.pending => (
        Icons.schedule,
        colorScheme.onSurfaceVariant,
      ),
      MigrationItemStatus.running => (Icons.autorenew, colorScheme.primary),
      MigrationItemStatus.success => (
        Icons.check_circle_outline,
        colorScheme.primary,
      ),
      MigrationItemStatus.failed => (Icons.error_outline, colorScheme.error),
      MigrationItemStatus.skipped => (
        Icons.remove_circle_outline,
        colorScheme.outline,
      ),
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      result.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      result.type.label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${result.status.label}'
                // 面板返回的耗时是秒（double），换算成 Duration 走统一格式化。
                '${result.duration > 0 ? ' · 耗时 ${formatDuration(Duration(milliseconds: (result.duration * 1000).round()))}' : ''}'
                '${result.endedAt != null ? ' · 结束于 ${formatDateTime(result.endedAt)}' : ''}',
                style: theme.textTheme.bodySmall?.copyWith(color: color),
              ),
              if (result.error.isNotEmpty) ...[
                const SizedBox(height: 4),
                SelectableText(
                  result.error,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
