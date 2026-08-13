import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/format.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/section_card.dart';
import '../models/disk_models.dart';
import '../providers/toolbox_disk_providers.dart';
import 'disk_dialogs.dart';
import 'disk_widgets.dart';

/// 「磁盘」标签页：磁盘与分区列表，以及挂载 / 卸载 / 格式化 / 初始化操作。
class DiskTab extends ConsumerStatefulWidget {
  const DiskTab({super.key});

  @override
  ConsumerState<DiskTab> createState() => _DiskTabState();
}

class _DiskTabState extends ConsumerState<DiskTab> {
  /// 当前正在执行的操作标识（设备名 + 动作），用于禁用按钮并展示进度。
  String? _busy;

  /// 确认流程（对话框链）是否已经在进行中。
  ///
  /// 破坏性操作的对话框是异步弹出的，同一帧内连点两次会叠出两条独立的确认链，
  /// 用户以为只确认了一次却执行了两次。这里在弹第一个对话框前就先上锁。
  bool _inFlow = false;

  bool get _locked => _busy != null || _inFlow;

  /// 串行执行一条「对话框确认 → 调接口」的流程，期间禁用本页全部入口。
  Future<void> _startFlow(Future<void> Function() flow) async {
    if (_locked) return;
    setState(() => _inFlow = true);
    try {
      await flow();
    } finally {
      if (mounted) setState(() => _inFlow = false);
    }
  }

  Future<void> _run(
    String key,
    Future<void> Function() action, {
    required String successMessage,
    bool refreshFstab = false,
  }) async {
    setState(() => _busy = key);
    try {
      await action();
      ref.invalidate(diskListProvider);
      ref.invalidate(lvmInfoProvider);
      if (refreshFstab) ref.invalidate(fstabProvider);
      if (!mounted) return;
      showSuccessSnack(context, successMessage);
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  // ------------------------------------------------------------------ 操作

  Future<void> _mount(PartitionInfo part) async {
    final params = await showMountDialog(
      context,
      device: part.name,
      sizeText: formatBytes(part.size),
      fsType: part.fstype,
    );
    if (params == null || !mounted) return;
    final confirmed = await showConfirmDialog(
      context,
      title: '挂载 ${part.name}？',
      content: params.writeFstab
          ? '将 /dev/${part.name} 挂载到 ${params.path}，'
                '并写入 /etc/fstab 实现开机自动挂载。'
          : '将 /dev/${part.name} 挂载到 ${params.path}（重启后失效）。',
      confirmText: '挂载',
    );
    if (!confirmed || !mounted) return;
    await _run(
      '${part.name}:mount',
      () => ref
          .read(toolboxDiskRepoProvider)
          .mount(
            device: part.name,
            path: params.path,
            writeFstab: params.writeFstab,
            mountOption: params.mountOption,
          ),
      successMessage: '${part.name} 已挂载到 ${params.path}',
      refreshFstab: params.writeFstab,
    );
  }

  Future<void> _umount(
    String name,
    String mountPoint, {
    bool onSystemDisk = false,
  }) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '卸载 $mountPoint？',
      content:
          '${onSystemDisk ? '注意：该挂载点位于系统盘，'
                    '若它是 /boot、/boot/efi 等系统目录，卸载后内核更新等操作会失败。\n\n' : ''}'
          '卸载后该挂载点下的数据将不可访问；'
          '若有程序正在使用该目录，卸载会失败。'
          '如已写入 fstab，重启后仍会自动挂载。',
      confirmText: '卸载',
      danger: true,
    );
    if (!confirmed || !mounted) return;
    await _run(
      '$name:umount',
      () => ref.read(toolboxDiskRepoProvider).umount(mountPoint),
      successMessage: '$mountPoint 已卸载',
    );
  }

  /// 格式化分区。
  ///
  /// 系统盘上的未挂载分区（EFI 引导分区、`/boot`、BIOS boot 保留分区等）格式化
  /// 后服务器将无法启动，且只能进控制台救援模式修复。因此在原本的三步确认之前
  /// **额外插入一步系统盘警示**，并把警示贯穿后续每一步——初始化（整盘）在系统盘
  /// 上是直接禁用的，分区级不能一刀切禁用（数据分区也可能落在系统盘上），
  /// 但必须让用户明确知道自己在动系统盘。
  Future<void> _format(DiskInfo disk, PartitionInfo part) async {
    final onSystemDisk = part.onSystemDisk;
    if (onSystemDisk) {
      final acknowledged = await showConfirmDialog(
        context,
        title: '这是系统盘上的分区',
        content:
            '/dev/${part.name} 位于系统盘 /dev/${disk.name}。\n\n'
            '系统盘上未挂载的分区通常是 EFI 引导分区、/boot 或 BIOS boot 保留分区，'
            '格式化后服务器将无法启动，只能通过服务商控制台进救援模式修复。\n\n'
            '只有在确认它是一块无用的数据分区时才继续。',
        confirmText: '我了解风险，继续',
        cancelText: '返回',
        danger: true,
      );
      if (!acknowledged || !mounted) return;
    }

    final fsType = await showFsTypeDialog(
      context,
      title: onSystemDisk ? '格式化系统盘上的分区' : '格式化分区',
      target: '/dev/${part.name}　${formatBytes(part.size)}',
      warning: onSystemDisk
          ? '该分区位于系统盘 /dev/${disk.name}。'
                '格式化会清空分区上的全部数据且无法恢复；'
                '若它参与系统启动，服务器将无法开机。'
          : '格式化会清空该分区上的全部数据，且无法恢复。',
    );
    if (fsType == null || !mounted) return;
    final confirmed = await showConfirmDialog(
      context,
      title: '格式化 /dev/${part.name}？',
      content:
          '${onSystemDisk ? '该分区在系统盘 /dev/${disk.name} 上。\n\n' : ''}'
          '该分区将被重新格式化为 $fsType，'
          '分区上的所有文件会被永久删除，操作不可撤销。',
      confirmText: '继续',
      danger: true,
    );
    if (!confirmed || !mounted) return;
    final typed = await showTypedConfirmDialog(
      context,
      title: onSystemDisk ? '最终确认（系统盘）' : '最终确认',
      message: onSystemDisk
          ? '即将格式化系统盘 /dev/${disk.name} 上的 /dev/${part.name} 为 $fsType。'
                '数据无法恢复，若该分区参与启动，服务器将无法开机。'
          : '即将格式化 /dev/${part.name} 为 $fsType，数据无法恢复。',
      requiredText: part.name,
      confirmText: '格式化',
    );
    if (!typed || !mounted) return;
    await _run(
      '${part.name}:format',
      () => ref
          .read(toolboxDiskRepoProvider)
          .format(device: part.name, fsType: fsType),
      successMessage: '${part.name} 已格式化为 $fsType',
    );
  }

  Future<void> _init(DiskInfo disk) async {
    final fsType = await showFsTypeDialog(
      context,
      title: '初始化磁盘',
      target: '/dev/${disk.name}　${formatBytes(disk.size)}',
      warning:
          '初始化会卸载该磁盘的所有分区、清除分区表，'
          '重新创建一个占满整盘的分区并格式化，全部数据永久丢失。',
    );
    if (fsType == null || !mounted) return;
    final confirmed = await showConfirmDialog(
      context,
      title: '初始化 /dev/${disk.name}？',
      content:
          '磁盘上现有的 ${disk.partitions.length} 个分区会被全部删除，'
          '并新建单个 $fsType 分区。此操作不可撤销，'
          '请确认该磁盘上没有需要保留的数据。',
      confirmText: '继续',
      danger: true,
    );
    if (!confirmed || !mounted) return;
    final typed = await showTypedConfirmDialog(
      context,
      title: '最终确认',
      message: '即将清空整块磁盘 /dev/${disk.name} 并格式化为 $fsType，数据无法恢复。',
      requiredText: disk.name,
      confirmText: '初始化',
    );
    if (!typed || !mounted) return;
    await _run(
      '${disk.name}:init',
      () => ref
          .read(toolboxDiskRepoProvider)
          .init(device: disk.name, fsType: fsType),
      successMessage: '${disk.name} 已初始化',
    );
  }

  Future<void> _showPartitions(DiskInfo disk) async {
    setState(() => _busy = '${disk.name}:detail');
    try {
      final devices = await ref
          .read(toolboxDiskRepoProvider)
          .partitions(disk.name);
      if (!mounted) return;
      await showPartitionDetailDialog(
        context,
        device: disk.name,
        devices: devices,
      );
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  // ------------------------------------------------------------------ 构建

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(diskListProvider);
    return async.when(
      loading: () => const LoadingView(message: '读取磁盘信息…'),
      error: (error, _) => ErrorView(
        error: error,
        onRetry: () => ref.invalidate(diskListProvider),
      ),
      data: (data) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(diskListProvider);
          await ref.read(diskListProvider.future);
        },
        child: data.disks.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  EmptyView(message: '未发现磁盘', icon: Icons.storage_outlined),
                ],
              )
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(top: 6, bottom: 32),
                itemCount: data.disks.length,
                itemBuilder: (context, index) =>
                    _diskCard(data.disks[index], data),
              ),
      ),
    );
  }

  Widget _diskCard(DiskInfo disk, DiskListData data) {
    final theme = Theme.of(context);
    final usage = data.df[disk.mountpoint];

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.storage_rounded, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '/dev/${disk.name}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${formatBytes(disk.size)} · ${disk.modelLabel} · '
                      '${disk.partitions.length} 个分区',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (disk.isSystemDisk)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: TagChip(
                    label: '系统盘',
                    icon: Icons.warning_amber_rounded,
                    color: theme.colorScheme.error,
                  ),
                ),
              _isBusy('${disk.name}:detail') || _isBusy('${disk.name}:init')
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: BusyIndicator(),
                    )
                  : PopupMenuButton<String>(
                      tooltip: '磁盘操作',
                      enabled: !_locked,
                      onSelected: (value) {
                        switch (value) {
                          case 'detail':
                            _showPartitions(disk);
                          case 'init':
                            _startFlow(() => _init(disk));
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem<String>(
                          value: 'detail',
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            leading: Icon(Icons.info_outline),
                            title: Text('分区详情'),
                          ),
                        ),
                        PopupMenuItem<String>(
                          value: 'init',
                          enabled: !disk.isSystemDisk,
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            leading: Icon(
                              Icons.delete_forever_outlined,
                              color: disk.isSystemDisk
                                  ? theme.disabledColor
                                  : theme.colorScheme.error,
                            ),
                            title: Text(
                              disk.isSystemDisk ? '初始化磁盘（系统盘禁止）' : '初始化磁盘',
                              style: TextStyle(
                                color: disk.isSystemDisk
                                    ? theme.disabledColor
                                    : theme.colorScheme.error,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ],
          ),
          const Divider(height: 20),
          if (disk.partitions.isEmpty)
            _wholeDiskRow(disk, usage)
          else
            for (final part in disk.partitions) _partitionRow(disk, part),
        ],
      ),
    );
  }

  bool _isBusy(String key) => _busy == key;

  /// 无分区表的整盘（可能整盘挂载，也可能是待初始化的裸盘）。
  Widget _wholeDiskRow(DiskInfo disk, DfInfo? usage) {
    final theme = Theme.of(context);
    if (disk.mountpoint.isEmpty) {
      return Row(
        children: [
          Expanded(
            child: Text(
              disk.fstype.isEmpty
                  ? '该磁盘没有分区，可通过右上角「初始化磁盘」创建分区并格式化。'
                  : '该磁盘没有分区表，整盘文件系统为 ${disk.fstype}，当前未挂载。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '整盘挂载于 ${disk.mountpoint}'
                '${disk.fstype.isEmpty ? '' : '（${disk.fstype}）'}',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            if (_isBusy('${disk.name}:umount'))
              const BusyIndicator()
            else if (disk.mountpoint != '/')
              TextButton(
                onPressed: _locked
                    ? null
                    : () => _startFlow(
                        () => _umount(
                          disk.name,
                          disk.mountpoint,
                          onSystemDisk: disk.isSystemDisk,
                        ),
                      ),
                child: const Text('卸载'),
              ),
          ],
        ),
        if (usage != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Expanded(child: UsageBar(percent: usage.percent)),
                const SizedBox(width: 10),
                Text(
                  '${formatBytes(usage.used)} / ${formatBytes(usage.size)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _partitionRow(DiskInfo disk, PartitionInfo part) {
    final theme = Theme.of(context);
    final busy =
        _isBusy('${part.name}:mount') ||
        _isBusy('${part.name}:umount') ||
        _isBusy('${part.name}:format');

    return Padding(
      padding: EdgeInsets.only(left: part.depth * 14.0, top: 6, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                part.type == 'lvm'
                    ? Icons.layers_outlined
                    : Icons.horizontal_split_rounded,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            part.name,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (part.type != 'part')
                          TagChip(
                            label: part.type,
                            color: theme.colorScheme.secondary,
                          ),
                        if (part.isRoot)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: TagChip(
                              label: '根分区',
                              color: theme.colorScheme.error,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        formatBytes(part.size),
                        if (part.fstype.isNotEmpty) part.fstype,
                        part.mounted ? part.mountpoint : '未挂载',
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: BusyIndicator(),
                )
              else
                PopupMenuButton<String>(
                  tooltip: '分区操作',
                  enabled: !_locked,
                  onSelected: (value) {
                    switch (value) {
                      case 'mount':
                        _startFlow(() => _mount(part));
                      case 'umount':
                        _startFlow(
                          () => _umount(
                            part.name,
                            part.mountpoint,
                            onSystemDisk: part.onSystemDisk,
                          ),
                        );
                      case 'format':
                        _startFlow(() => _format(disk, part));
                    }
                  },
                  itemBuilder: (context) => [
                    if (!part.mounted)
                      const PopupMenuItem<String>(
                        value: 'mount',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: Icon(Icons.playlist_add_check_rounded),
                          title: Text('挂载'),
                        ),
                      ),
                    if (part.mounted)
                      PopupMenuItem<String>(
                        value: 'umount',
                        enabled: !part.isRoot,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: const Icon(Icons.eject_outlined),
                          title: Text(part.isRoot ? '卸载（根分区禁止）' : '卸载'),
                        ),
                      ),
                    // 格式化只对未挂载分区开放；位于系统盘时额外标注，
                    // 点开后会先弹一层「这是系统盘上的分区」警示。
                    if (!part.mounted)
                      PopupMenuItem<String>(
                        value: 'format',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: Icon(
                            Icons.warning_amber_rounded,
                            color: theme.colorScheme.error,
                          ),
                          title: Text(
                            part.onSystemDisk ? '格式化（系统盘分区）' : '格式化',
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                          subtitle: part.onSystemDisk
                              ? Text(
                                  '可能是引导分区，格式化后无法开机',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.error,
                                  ),
                                )
                              : null,
                        ),
                      ),
                  ],
                ),
            ],
          ),
          if (part.mounted)
            Padding(
              padding: const EdgeInsets.only(left: 26, top: 4),
              child: Row(
                children: [
                  Expanded(child: UsageBar(percent: part.percent)),
                  const SizedBox(width: 10),
                  Text(
                    '${formatBytes(part.used)} / '
                    '${formatBytes(part.used + part.avail)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
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
