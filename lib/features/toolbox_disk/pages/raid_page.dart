import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/section_card.dart';
import '../models/raid_models.dart';
import '../providers/toolbox_disk_providers.dart';
import '../widgets/disk_widgets.dart';

/// RAID 阵列状态页（`/toolbox/disk/raid`）。
///
/// 面板按 mdadm → MegaRAID → HP Smart Array → Adaptec 顺序探测，
/// 需要服务器安装对应的管理工具（storcli / ssacli / arcconf）。
class RaidPage extends ConsumerWidget {
  const RaidPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(raidInfoProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('RAID 阵列'),
        actions: [
          A11yIconButton(
            tooltip: '刷新 RAID 状态',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(raidInfoProvider),
          ),
        ],
      ),
      body: async.when(
        loading: () => const LoadingView(message: '探测 RAID 配置…'),
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(raidInfoProvider),
        ),
        data: (info) {
          if (!info.available) {
            return EmptyView(
              message: info.message.isEmpty ? '未检测到 RAID 配置' : info.message,
              icon: Icons.grid_view_rounded,
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(raidInfoProvider);
              await ref.read(raidInfoProvider.future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 6, bottom: 32),
              children: [
                SectionCard(
                  child: Row(
                    children: [
                      Icon(
                        Icons.grid_view_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          info.typeLabel,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      TagChip(label: '${info.arrays.length} 个阵列'),
                    ],
                  ),
                ),
                for (var i = 0; i < info.controllers.length; i++)
                  _controllerCard(context, info.controllers[i], i),
                if (info.arrays.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: EmptyView(
                      message: '没有找到 RAID 阵列',
                      icon: Icons.grid_off_rounded,
                    ),
                  )
                else
                  for (final array in info.arrays) _arrayCard(context, array),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _controllerCard(
    BuildContext context,
    RaidController controller,
    int index,
  ) {
    return SectionCard(
      title: '控制器 #${index + 1}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoRow(label: '型号', value: controller.model),
          if (controller.serial.isNotEmpty)
            InfoRow(label: '序列号', value: controller.serial, monospace: true),
          if (controller.firmware.isNotEmpty)
            InfoRow(label: '固件', value: controller.firmware),
          if (controller.cacheSize.isNotEmpty)
            InfoRow(label: '缓存', value: controller.cacheSize),
        ],
      ),
    );
  }

  Widget _arrayCard(BuildContext context, RaidArray array) {
    final theme = Theme.of(context);
    final stateColor = _healthColor(theme, raidHealthOf(array.state));

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  array.name.isEmpty ? '未命名阵列' : array.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 阵列状态是 mdadm / storcli 的原始文本，可能很长。
              Flexible(
                child: TagChip(
                  label: array.state.isEmpty ? '状态未知' : array.state,
                  color: stateColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (array.raidLevel.isNotEmpty)
            InfoRow(label: 'RAID 级别', value: array.raidLevel),
          if (array.size.isNotEmpty) InfoRow(label: '容量', value: array.size),
          if (array.stripSize.isNotEmpty)
            InfoRow(label: '条带大小', value: array.stripSize),
          if (array.activeDevices > 0 || array.totalDevices > 0)
            InfoRow(
              label: '成员磁盘',
              value: '${array.activeDevices} / ${array.totalDevices}',
              valueColor: array.totalDevices > 0 &&
                      array.activeDevices < array.totalDevices
                  ? theme.colorScheme.error
                  : null,
            ),
          if (array.rebuildPct.isNotEmpty)
            InfoRow(
              label: '重建进度',
              value: array.rebuildPct,
              valueColor: theme.colorScheme.tertiary,
            ),
          if (array.devices.isNotEmpty) ...[
            const Divider(height: 20),
            Text(
              '成员磁盘',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            for (final device in array.devices)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.storage_outlined,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            device.name.isEmpty ? '未知设备' : device.name,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontFamily: 'monospace',
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [
                              if (device.slot.isNotEmpty) '槽位 ${device.slot}',
                              if (device.size.isNotEmpty) device.size,
                              if (device.model.isNotEmpty) device.model,
                              if (device.serial.isNotEmpty)
                                'SN ${device.serial}',
                            ].join(' · '),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: TagChip(
                        label: device.state.isEmpty ? '未知' : device.state,
                        color: _healthColor(theme, raidHealthOf(device.state)),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Color _healthColor(ThemeData theme, RaidHealth health) {
    switch (health) {
      case RaidHealth.good:
        return theme.colorScheme.primary;
      case RaidHealth.warning:
        return theme.colorScheme.tertiary;
      case RaidHealth.bad:
        return theme.colorScheme.error;
      case RaidHealth.unknown:
        return theme.colorScheme.onSurfaceVariant;
    }
  }
}
