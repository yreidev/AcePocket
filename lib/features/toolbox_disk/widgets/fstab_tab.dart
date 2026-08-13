import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/section_card.dart';
import '../models/disk_models.dart';
import '../providers/toolbox_disk_providers.dart';
import 'disk_widgets.dart';

/// 「自动挂载」标签页：`/etc/fstab` 条目查看与删除。
///
/// 新增条目在「磁盘」页挂载分区时勾选「开机自动挂载」即可写入。
class FstabTab extends ConsumerStatefulWidget {
  const FstabTab({super.key});

  @override
  ConsumerState<FstabTab> createState() => _FstabTabState();
}

class _FstabTabState extends ConsumerState<FstabTab> {
  String? _busy;

  /// 确认对话框是否已经弹出，避免连点删除两次同一条目。
  bool _inFlow = false;

  bool get _locked => _busy != null || _inFlow;

  Future<void> _delete(FstabEntry entry) async {
    if (_locked) return;
    setState(() => _inFlow = true);
    try {
      final confirmed = await showConfirmDialog(
        context,
        title: '删除 ${entry.mountPoint} 的自动挂载？',
        content:
            '将从 /etc/fstab 中移除该条目，系统重启后不再自动挂载，'
            '面板随后会执行 mount -a 重新加载配置。当前已挂载的分区不会被卸载。',
        confirmText: '删除',
        danger: true,
      );
      if (!confirmed || !mounted) return;
      setState(() => _busy = entry.mountPoint);
      try {
        await ref.read(toolboxDiskRepoProvider).deleteFstab(entry.mountPoint);
        ref.invalidate(fstabProvider);
        ref.invalidate(diskListProvider);
        if (!mounted) return;
        showSuccessSnack(context, '已删除 ${entry.mountPoint} 的自动挂载配置');
      } catch (e) {
        if (!mounted) return;
        showErrorSnack(context, e);
      } finally {
        if (mounted) setState(() => _busy = null);
      }
    } finally {
      if (mounted) setState(() => _inFlow = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(fstabProvider);

    return async.when(
      loading: () => const LoadingView(message: '读取 /etc/fstab…'),
      error: (error, _) =>
          ErrorView(error: error, onRetry: () => ref.invalidate(fstabProvider)),
      data: (entries) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(fstabProvider);
          await ref.read(fstabProvider.future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: 6, bottom: 32),
          children: [
            const NoticeBar(
              text:
                  '/etc/fstab 决定开机时自动挂载哪些文件系统。'
                  '条目错误可能导致系统无法正常启动，请谨慎删除。'
                  '如需新增，请在「磁盘」页挂载分区时勾选「开机自动挂载」。',
              icon: Icons.info_outline,
            ),
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: EmptyView(
                  message: '没有可解析的 fstab 条目',
                  icon: Icons.playlist_remove_rounded,
                ),
              )
            else
              for (final entry in entries) _entryCard(entry),
          ],
        ),
      ),
    );
  }

  Widget _entryCard(FstabEntry entry) {
    final theme = Theme.of(context);
    final busy = _busy == entry.mountPoint;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.link_rounded,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.mountPoint,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              if (entry.isRoot)
                Flexible(
                  child: TagChip(label: '根挂载点', color: theme.colorScheme.error),
                ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: BusyIndicator(),
                )
              else if (!entry.isRoot)
                A11yIconButton(
                  tooltip: '删除 ${entry.mountPoint} 的自动挂载条目',
                  icon: Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: theme.colorScheme.error,
                  ),
                  onPressed: _locked ? null : () => _delete(entry),
                ),
            ],
          ),
          const SizedBox(height: 4),
          InfoRow(label: '设备', value: entry.device, monospace: true),
          InfoRow(label: '文件系统', value: entry.fsType),
          InfoRow(label: '挂载选项', value: entry.options, monospace: true),
          InfoRow(
            label: '备份 / 检查',
            value:
                '${entry.dump.isEmpty ? '0' : entry.dump} / '
                '${entry.pass.isEmpty ? '0' : entry.pass}',
          ),
        ],
      ),
    );
  }
}
