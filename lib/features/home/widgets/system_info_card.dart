import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/widgets/section_card.dart';
import '../providers/home_providers.dart';
import 'formatters.dart';
import 'info_row.dart';

/// 系统与面板信息卡片。
class SystemInfoCard extends ConsumerWidget {
  const SystemInfoCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(systemInfoProvider);
    final panel = ref.watch(panelInfoProvider).value;

    return SectionCard(
      title: '系统信息',
      child: async.when(
        loading: () => const SizedBox(
          height: 64,
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
          onRetry: () => ref.invalidate(systemInfoProvider),
        ),
        data: (info) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InfoRow(label: '主机名', value: info.hostname),
            InfoRow(
              label: '操作系统',
              value: info.osName,
              valueColor: info.osSupported && !info.osEol
                  ? null
                  : theme.colorScheme.error,
            ),
            if (!info.osSupported) _hint(context, '当前系统版本低于面板要求，部分功能可能不可用'),
            if (info.osEol) _hint(context, '当前系统已停止官方维护（EOL），建议尽快升级'),
            InfoRow(label: '内核', value: info.kernelVersion, monospace: true),
            InfoRow(label: '架构', value: info.kernelArch),
            InfoRow(label: '进程数', value: '${info.procs}'),
            InfoRow(label: '运行时长', value: formatUptime(info.uptime)),
            InfoRow(label: '启动时间', value: formatUnixSeconds(info.bootTime)),
            Divider(color: theme.colorScheme.outlineVariant, height: 20),
            if (panel != null) InfoRow(label: '面板名称', value: panel.name),
            InfoRow(label: '面板版本', value: info.panelVersion, monospace: true),
            if (info.commitHash.isNotEmpty)
              InfoRow(
                label: '构建版本',
                value: info.commitHash.length > 12
                    ? info.commitHash.substring(0, 12)
                    : info.commitHash,
                monospace: true,
              ),
            if (info.buildTime.isNotEmpty)
              InfoRow(label: '构建时间', value: info.buildTime),
            if (info.goVersion.isNotEmpty)
              InfoRow(label: 'Go 版本', value: info.goVersion, monospace: true),
          ],
        ),
      ),
    );
  }

  Widget _hint(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 14,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
