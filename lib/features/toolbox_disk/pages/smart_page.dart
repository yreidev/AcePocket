import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/format.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/section_card.dart';
import '../models/smart_models.dart';
import '../providers/toolbox_disk_providers.dart';
import '../widgets/disk_widgets.dart';

/// SMART 健康页（`/toolbox/disk/smart`）。
///
/// 依赖服务器安装 smartmontools；未安装时面板会在
/// `GET /toolbox_disk/smart/disks` 中返回 `available = false` 与安装提示。
class SmartPage extends ConsumerWidget {
  const SmartPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final disksAsync = ref.watch(smartDisksProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('SMART 健康'),
        actions: [
          A11yIconButton(
            tooltip: '刷新 SMART 数据',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(smartDisksProvider);
              final selected = ref.read(selectedSmartDiskProvider);
              if (selected != null) ref.invalidate(smartInfoProvider(selected));
            },
          ),
        ],
      ),
      body: disksAsync.when(
        loading: () => const LoadingView(message: '检测支持 SMART 的磁盘…'),
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(smartDisksProvider),
        ),
        data: (list) {
          if (!list.available) {
            return EmptyView(
              message: list.message.isEmpty
                  ? '服务器未安装 smartmontools，无法读取 SMART 信息'
                  : list.message,
              icon: Icons.monitor_heart_outlined,
            );
          }
          if (list.disks.isEmpty) {
            return const EmptyView(
              message: '未发现支持 SMART 的磁盘（虚拟化磁盘通常不支持）',
              icon: Icons.monitor_heart_outlined,
            );
          }

          final stored = ref.watch(selectedSmartDiskProvider);
          final selected =
              list.disks.any((disk) => disk.name == stored) && stored != null
                  ? stored
                  : list.disks.first.name;

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(smartDisksProvider);
              ref.invalidate(smartInfoProvider(selected));
              await ref.read(smartInfoProvider(selected).future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 6, bottom: 32),
              children: [
                _diskSelector(context, ref, list, selected),
                _SmartDetail(device: selected),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _diskSelector(
    BuildContext context,
    WidgetRef ref,
    SmartDiskList list,
    String selected,
  ) {
    return SectionCard(
      title: '选择磁盘',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final disk in list.disks)
            ChoiceChip(
              label: Text(disk.label),
              selected: disk.name == selected,
              onSelected: (_) => ref
                  .read(selectedSmartDiskProvider.notifier)
                  .state = disk.name,
            ),
        ],
      ),
    );
  }
}

/// 单块磁盘的 SMART 详情。
class _SmartDetail extends ConsumerWidget {
  const _SmartDetail({required this.device});

  final String device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(smartInfoProvider(device));

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: LoadingView(message: '读取 SMART 数据…'),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: ErrorView(
          error: error,
          onRetry: () => ref.invalidate(smartInfoProvider(device)),
        ),
      ),
      data: (info) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _overviewCard(context, info),
          _attributesCard(context, info),
          if (info.messages.isNotEmpty)
            SectionCard(
              title: 'smartctl 提示',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final message in info.messages)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        message,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _overviewCard(BuildContext context, SmartInfo info) {
    final theme = Theme.of(context);
    final passed = info.healthPassed;
    final temperature = info.temperature;
    final tempColor = temperature == null
        ? theme.colorScheme.onSurfaceVariant
        : temperature <= 40
            ? theme.colorScheme.primary
            : temperature <= 50
                ? theme.colorScheme.tertiary
                : theme.colorScheme.error;

    return SectionCard(
      title: '基本信息',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (passed != null)
                Flexible(
                  child: TagChip(
                    label: passed ? '健康状态 正常' : '健康状态 异常',
                    icon:
                        passed ? Icons.verified_outlined : Icons.error_outline,
                    color: passed
                        ? theme.colorScheme.primary
                        : theme.colorScheme.error,
                  ),
                ),
              const Spacer(),
              if (temperature != null)
                Text(
                  '${temperature.toStringAsFixed(0)} °C',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: tempColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const Divider(height: 20),
          InfoRow(label: '设备', value: '/dev/$device', monospace: true),
          InfoRow(label: '型号', value: info.modelName),
          InfoRow(label: '序列号', value: info.serialNumber, monospace: true),
          InfoRow(label: '固件版本', value: info.firmware),
          if (info.capacityBytes > 0)
            InfoRow(label: '容量', value: formatBytes(info.capacityBytes)),
          InfoRow(label: '接口', value: info.interfaceName),
          if (info.rotationLabel.isNotEmpty)
            InfoRow(label: '转速', value: info.rotationLabel),
          if (info.powerOnHours != null)
            InfoRow(
              label: '通电时长',
              value: '${info.powerOnHours!.toStringAsFixed(0)} 小时',
            ),
          if (info.powerCycleCount != null)
            InfoRow(
              label: '通电次数',
              value: '${info.powerCycleCount!.toStringAsFixed(0)} 次',
            ),
          if (info.deviceTime.isNotEmpty)
            InfoRow(label: '采样时间', value: info.deviceTime),
        ],
      ),
    );
  }

  Widget _attributesCard(BuildContext context, SmartInfo info) {
    final theme = Theme.of(context);
    if (info.attributes.isEmpty) {
      return SectionCard(
        title: info.isNvme ? 'NVMe 健康日志' : 'SMART 属性',
        child: Text(
          '该设备没有返回可解析的 SMART 属性',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return SectionCard(
      title: info.isNvme ? 'NVMe 健康日志' : 'SMART 属性（${info.attributes.length}）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final attr in info.attributes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          attr.id.isEmpty
                              ? attr.name
                              : '${attr.id}　${attr.name}',
                          style: theme.textTheme.bodyMedium,
                        ),
                        if (!info.isNvme)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '当前 ${attr.value} · 最差 ${attr.worst} · '
                              '阈值 ${attr.threshold}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  // 原始值来自 smartctl，个别属性会是
                  // 「12345 (Average 678)」这类长串；不加 Flexible
                  // 会把左侧 Expanded 挤成 0 宽并触发横向溢出。
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          info.isNvme ? attr.value : attr.raw,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontFamily: 'monospace',
                          ),
                        ),
                        if (!info.isNvme)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: TagChip(
                              label: attr.failed ? attr.whenFailed : '正常',
                              color: attr.failed
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.primary,
                            ),
                          ),
                      ],
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
