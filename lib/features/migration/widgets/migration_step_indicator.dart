import 'package:flutter/material.dart';

import '../providers/migration_providers.dart';

/// 迁移向导的步骤指示条（连接 → 预检 → 选择 → 迁移 → 完成）。
class MigrationStepIndicator extends StatelessWidget {
  const MigrationStepIndicator({super.key, required this.stage});

  final MigrationStage stage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final current = stage.index0;
    final stages = MigrationStage.values;
    // 圆点随系统字号放大，否则 200% 字号下序号会被圆圈裁掉。
    final textScaler = MediaQuery.textScalerOf(context);
    final circleSize = textScaler.scale(26).clamp(26.0, 44.0);

    return Semantics(
      container: true,
      // 逐个念「1 连接 2 预检…」对读屏用户毫无用处，合并成一句进度描述。
      label:
          '迁移进度：共 ${stages.length} 步，当前第 ${current + 1} 步 '
          '${stages[current].label}',
      child: ExcludeSemantics(
        // 不再固定 62dp 高度：200% 系统字号下步骤名会被垂直裁切。
        // 改为横向 SingleChildScrollView + Row，高度由内容撑开。
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < stages.length; index++) ...[
                if (index != 0)
                  Container(
                    width: 28,
                    height: 2,
                    // 与圆点圆心对齐；用 top 而非 bottom，
                    // 这样字号放大后连接线不会跟着标签往下跑。
                    margin: EdgeInsets.only(top: circleSize / 2 - 1),
                    color: index <= current
                        ? colorScheme.primary
                        : colorScheme.surfaceContainerHighest,
                  ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: circleSize,
                      height: circleSize,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: index <= current
                            ? colorScheme.primary
                            : colorScheme.surfaceContainerHighest,
                        shape: BoxShape.circle,
                      ),
                      child: index < current
                          ? Icon(
                              Icons.check,
                              size: circleSize * 0.6,
                              color: colorScheme.onPrimary,
                            )
                          : Text(
                              '${index + 1}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: index == current
                                    ? colorScheme.onPrimary
                                    : colorScheme.onSurfaceVariant,
                              ),
                            ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      stages[index].label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: index == current
                            ? colorScheme.primary
                            : index < current
                            ? colorScheme.onSurface
                            : colorScheme.onSurfaceVariant,
                        fontWeight: index == current ? FontWeight.w600 : null,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
