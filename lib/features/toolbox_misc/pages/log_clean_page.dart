import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/utils/format.dart';
import '../../../core/version/panel_feature.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/feature_gate.dart';
import '../../../core/widgets/section_card.dart';
import '../models/log_models.dart';
import '../providers/toolbox_misc_providers.dart';
import '../widgets/toolbox_tiles.dart';

/// 日志清理页：按类型扫描可清理内容并释放磁盘空间。
///
/// 接口见 `internal/route/toolbox_log.go`
/// （GET `/toolbox_log/scan?type=`、POST `/toolbox_log/clean`）。
class LogCleanPage extends ConsumerStatefulWidget {
  const LogCleanPage({super.key});

  @override
  ConsumerState<LogCleanPage> createState() => _LogCleanPageState();
}

class _LogCleanPageState extends ConsumerState<LogCleanPage> {
  @override
  void initState() {
    super.initState();
    // 首次进入自动扫描一遍，给出可清理项概览。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final states = ref.read(logCleanProvider);
      final needScan = states.values.every(
        (s) => !s.scanned && !s.busy && s.error == null,
      );
      if (needScan) ref.read(logCleanProvider.notifier).scanAll();
    });
  }

  Future<void> _clean(LogTypeDef type) async {
    final state = ref.read(logCleanProvider)[type.key];
    final confirmed = await showConfirmDialog(
      context,
      title: '清理${type.title}？',
      content:
          '将删除 ${type.title}（${state?.items.length ?? 0} 项）'
          '并释放对应磁盘空间，该操作不可恢复。',
      confirmText: '清理',
      danger: true,
    );
    if (!confirmed) return;
    try {
      final cleaned = await ref.read(logCleanProvider.notifier).clean(type.key);
      if (!mounted) return;
      showSuccessSnack(context, '${type.title}已清理，释放 $cleaned');
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    }
  }

  Future<void> _cleanAll(List<LogTypeDef> types) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '清理全部日志？',
      content:
          '将依次清理 ${types.map((t) => t.title).join('、')}，'
          '删除后不可恢复。',
      confirmText: '全部清理',
      danger: true,
    );
    if (!confirmed) return;
    for (final type in types) {
      try {
        final cleaned = await ref
            .read(logCleanProvider.notifier)
            .clean(type.key);
        if (!mounted) return;
        showSuccessSnack(context, '${type.title}已清理，释放 $cleaned');
      } catch (e) {
        if (!mounted) return;
        showErrorSnack(context, '${type.title}清理失败：${describeError(e)}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final states = ref.watch(logCleanProvider);
    final notifier = ref.read(logCleanProvider.notifier);

    final anyBusy = states.values.any((s) => s.busy);
    final cleanable = kLogTypes
        .where((t) => (states[t.key]?.items.isNotEmpty ?? false))
        .toList();
    final totalItems = states.values.fold<int>(
      0,
      (sum, s) => sum + s.items.length,
    );
    final totalBytes = states.values.fold<int>(
      0,
      (sum, s) => sum + s.totalBytes,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('日志清理'),
        actions: [
          A11yIconButton(
            tooltip: '重新扫描全部日志',
            icon: const Icon(Icons.refresh),
            onPressed: anyBusy ? null : notifier.scanAll,
          ),
        ],
      ),
      body: Column(
        children: [
          const FeatureUnsupportedBanner(feature: PanelFeature.toolboxLog),
          Expanded(
            child: RefreshIndicator(
              onRefresh: notifier.scanAll,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  SectionCard(
                    title: '扫描概览',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _summary(
                                label: '可清理项',
                                value: '$totalItems',
                              ),
                            ),
                            Expanded(
                              child: _summary(
                                label: '预计可释放',
                                value: formatBytes(totalBytes),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '容器镜像等条目没有精确大小，未计入「预计可释放」。'
                          '清理操作不可恢复，请确认相关日志已无需保留。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: anyBusy ? null : notifier.scanAll,
                                icon: anyBusy
                                    ? const BusyIndicator(size: 16)
                                    : const Icon(Icons.search),
                                label: const Text('全部扫描'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: anyBusy || cleanable.isEmpty
                                    ? null
                                    : () => _cleanAll(cleanable),
                                icon: const Icon(
                                  Icons.cleaning_services_outlined,
                                ),
                                label: const Text('全部清理'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  for (final type in kLogTypes)
                    _typeCard(type, states[type.key] ?? const LogScanState()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summary({required String label, required String value}) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _typeCard(LogTypeDef type, LogScanState state) {
    final theme = Theme.of(context);
    final notifier = ref.read(logCleanProvider.notifier);

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(type.icon, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(type.title, style: theme.textTheme.titleSmall),
                    Text(
                      type.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (state.busy)
                const BusyIndicator()
              else if (state.items.isNotEmpty)
                TagChip(
                  label:
                      '${state.items.length} 项 · ${formatBytes(state.totalBytes)}',
                  color: theme.colorScheme.tertiary,
                ),
            ],
          ),
          if (state.error != null) ...[
            const SizedBox(height: 10),
            SectionErrorTile(
              message: describeError(state.error!),
              onRetry: () => notifier.scan(type.key),
            ),
          ] else if (state.scanned && state.items.isEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '没有可清理的内容',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ] else if (state.items.isNotEmpty) ...[
            const SizedBox(height: 8),
            _itemList(state),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: state.busy ? null : () => notifier.scan(type.key),
                  icon: const Icon(Icons.search, size: 18),
                  label: Text(state.scanned ? '重新扫描' : '扫描'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: state.busy || state.items.isEmpty
                      ? null
                      : () => _clean(type),
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: const Text('清理'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _itemList(LogScanState state) {
    final theme = Theme.of(context);
    const previewCount = 5;
    final preview = state.items.take(previewCount).toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in preview)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    item.size,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          if (state.items.length > previewCount)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: TextButton(
                onPressed: () => _showAllItems(state),
                child: Text('查看全部 ${state.items.length} 项'),
              ),
            ),
        ],
      ),
    );
  }

  void _showAllItems(LogScanState state) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          builder: (context, controller) => ListView.separated(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            itemCount: state.items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = state.items[index];
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(item.name, style: theme.textTheme.bodyMedium),
                subtitle: Text(
                  item.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: Text(item.size, style: theme.textTheme.bodySmall),
              );
            },
          ),
        );
      },
    );
  }
}
