import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/app_snack.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/section_card.dart';
import '../models/disk_models.dart';
import '../models/lvm_models.dart';
import '../providers/toolbox_disk_providers.dart';
import 'disk_dialogs.dart';
import 'disk_widgets.dart';

/// 「LVM」标签页：物理卷 / 卷组 / 逻辑卷的查看、创建、删除与扩容。
class LvmTab extends ConsumerStatefulWidget {
  const LvmTab({super.key});

  @override
  ConsumerState<LvmTab> createState() => _LvmTabState();
}

class _LvmTabState extends ConsumerState<LvmTab> {
  String? _busy;

  /// 确认流程（对话框链）是否已经在进行中，避免连点弹出多条确认链。
  bool _inFlow = false;

  bool _isBusy(String key) => _busy == key;

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
  }) async {
    setState(() => _busy = key);
    try {
      await action();
      ref.invalidate(lvmInfoProvider);
      ref.invalidate(diskListProvider);
      if (!mounted) return;
      showSuccessSnack(context, successMessage);
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  // ------------------------------------------------------------------ 物理卷

  Future<void> _createPv(DiskListData? disks, LvmInfo lvm) async {
    final existing = lvm.pvs.map((pv) => pv.name).toSet();
    final candidates =
        (disks?.pvCandidates ?? const <({String device, int size})>[])
            .where((item) => !existing.contains('/dev/${item.device}'))
            .toList();
    final device = await showDeviceSelectDialog(
      context,
      title: '创建物理卷',
      helper: '选择要初始化为 LVM 物理卷的设备（会写入 LVM 元数据）。',
      candidates: candidates,
    );
    if (device == null || !mounted) return;
    final confirmed = await showConfirmDialog(
      context,
      title: '在 /dev/$device 上创建物理卷？',
      content: '设备会被写入 LVM 元数据。若设备上存在文件系统或数据，可能因此不可用。',
      confirmText: '创建',
      danger: true,
    );
    if (!confirmed || !mounted) return;
    await _run(
      'pv:create',
      () => ref.read(toolboxDiskRepoProvider).createPv(device),
      successMessage: '物理卷 /dev/$device 已创建',
    );
  }

  Future<void> _removePv(PhysicalVolume pv) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除物理卷 ${pv.name}？',
      content: '将执行 pvremove 清除该设备上的 LVM 元数据。'
          '若该物理卷仍属于卷组，删除会失败，请先移除卷组。',
      confirmText: '删除',
      danger: true,
    );
    if (!confirmed || !mounted) return;
    await _run(
      'pv:${pv.name}',
      () => ref.read(toolboxDiskRepoProvider).removePv(pv.name),
      successMessage: '物理卷 ${pv.name} 已删除',
    );
  }

  // ------------------------------------------------------------------ 卷组

  Future<void> _createVg(LvmInfo lvm) async {
    final params = await showCreateVgDialog(context, freePvs: lvm.freePvs);
    if (params == null || !mounted) return;
    final confirmed = await showConfirmDialog(
      context,
      title: '创建卷组 ${params.name}？',
      content: '将使用 ${params.devices.length} 个物理卷创建卷组：\n'
          '${params.devices.join('\n')}',
      confirmText: '创建',
    );
    if (!confirmed || !mounted) return;
    await _run(
      'vg:create',
      () => ref
          .read(toolboxDiskRepoProvider)
          .createVg(name: params.name, devices: params.devices),
      successMessage: '卷组 ${params.name} 已创建',
    );
  }

  Future<void> _removeVg(VolumeGroup vg) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除卷组 ${vg.name}？',
      content: '将执行 vgremove -f，卷组内的 ${vg.lvCount} 个逻辑卷'
          '及其上的全部数据都会被删除，操作不可撤销。',
      confirmText: '继续',
      danger: true,
    );
    if (!confirmed || !mounted) return;
    final typed = await showTypedConfirmDialog(
      context,
      title: '最终确认',
      message: '即将强制删除卷组 ${vg.name}，其中的逻辑卷与数据无法恢复。',
      requiredText: vg.name,
      confirmText: '删除卷组',
    );
    if (!typed || !mounted) return;
    await _run(
      'vg:${vg.name}',
      () => ref.read(toolboxDiskRepoProvider).removeVg(vg.name),
      successMessage: '卷组 ${vg.name} 已删除',
    );
  }

  // ------------------------------------------------------------------ 逻辑卷

  Future<void> _createLv(LvmInfo lvm) async {
    final params = await showCreateLvDialog(context, vgs: lvm.vgs);
    if (params == null || !mounted) return;
    final confirmed = await showConfirmDialog(
      context,
      title: '创建逻辑卷 ${params.name}？',
      content: '将在卷组 ${params.vgName} 中划出 ${params.sizeGb}GB 创建逻辑卷。'
          '创建后还需要格式化并挂载才能使用。',
      confirmText: '创建',
    );
    if (!confirmed || !mounted) return;
    await _run(
      'lv:create',
      () => ref.read(toolboxDiskRepoProvider).createLv(
            name: params.name,
            vgName: params.vgName,
            sizeGb: params.sizeGb,
          ),
      successMessage: '逻辑卷 ${params.name} 已创建',
    );
  }

  Future<void> _removeLv(LogicalVolume lv) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除逻辑卷 ${lv.name}？',
      content: '将执行 lvremove -f 删除 ${lv.path}，'
          '卷上的全部数据会被永久删除，操作不可撤销。',
      confirmText: '继续',
      danger: true,
    );
    if (!confirmed || !mounted) return;
    final typed = await showTypedConfirmDialog(
      context,
      title: '最终确认',
      message: '即将删除逻辑卷 ${lv.path}，数据无法恢复。',
      requiredText: lv.name,
      confirmText: '删除逻辑卷',
    );
    if (!typed || !mounted) return;
    await _run(
      'lv:${lv.path}',
      () => ref.read(toolboxDiskRepoProvider).removeLv(lv.path),
      successMessage: '逻辑卷 ${lv.name} 已删除',
    );
  }

  Future<void> _extendLv(LogicalVolume lv) async {
    final params = await showExtendLvDialog(context, lv: lv);
    if (params == null || !mounted) return;
    final confirmed = await showConfirmDialog(
      context,
      title: '扩容 ${lv.name}？',
      content: '将为 ${lv.path} 增加 ${params.sizeGb}GB'
          '${params.resize ? '，并同步扩展其上的文件系统' : '（不扩展文件系统）'}。',
      confirmText: '扩容',
    );
    if (!confirmed || !mounted) return;
    await _run(
      'lv:${lv.path}',
      () => ref.read(toolboxDiskRepoProvider).extendLv(
            path: lv.path,
            sizeGb: params.sizeGb,
            resize: params.resize,
          ),
      successMessage: '逻辑卷 ${lv.name} 已扩容 ${params.sizeGb}GB',
    );
  }

  // ------------------------------------------------------------------ 构建

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(lvmInfoProvider);
    final disks = ref.watch(diskListProvider).valueOrNull;

    return async.when(
      loading: () => const LoadingView(message: '读取 LVM 信息…'),
      error: (error, _) => ErrorView(
        error: error,
        onRetry: () => ref.invalidate(lvmInfoProvider),
      ),
      data: (lvm) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(lvmInfoProvider);
          await ref.read(lvmInfoProvider.future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: 6, bottom: 32),
          children: [
            if (lvm.isEmpty)
              const NoticeBar(
                text: '当前服务器没有检测到 LVM 卷。若系统未安装 lvm2 工具包，'
                    '相关命令不可用，创建操作也会失败。',
              ),
            _pvCard(lvm, disks),
            _vgCard(lvm),
            _lvCard(lvm),
          ],
        ),
      ),
    );
  }

  Widget _pvCard(LvmInfo lvm, DiskListData? disks) {
    final theme = Theme.of(context);
    return SectionCard(
      title: '物理卷（${lvm.pvs.length}）',
      trailing: _isBusy('pv:create')
          ? const BusyIndicator()
          : TextButton.icon(
              onPressed: _locked
                  ? null
                  : () => _startFlow(() => _createPv(disks, lvm)),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('创建'),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (lvm.pvs.isEmpty)
            Text(
              '暂无物理卷',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          for (final pv in lvm.pvs)
            _itemRow(
              icon: Icons.album_outlined,
              title: pv.name,
              subtitle: '卷组 ${pv.vgName.isEmpty ? '未分配' : pv.vgName}'
                  ' · 容量 ${pv.size}'
                  '${pv.free.isEmpty ? '' : ' · 空闲 ${pv.free}'}',
              busy: _isBusy('pv:${pv.name}'),
              actions: [
                _dangerAction(
                  tooltip: '删除物理卷 ${pv.name}',
                  onPressed: () => _startFlow(() => _removePv(pv)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _vgCard(LvmInfo lvm) {
    final theme = Theme.of(context);
    return SectionCard(
      title: '卷组（${lvm.vgs.length}）',
      trailing: _isBusy('vg:create')
          ? const BusyIndicator()
          : TextButton.icon(
              onPressed:
                  _locked ? null : () => _startFlow(() => _createVg(lvm)),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('创建'),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (lvm.vgs.isEmpty)
            Text(
              '暂无卷组',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          for (final vg in lvm.vgs)
            _itemRow(
              icon: Icons.folder_special_outlined,
              title: vg.name,
              subtitle: 'PV ${vg.pvCount} · LV ${vg.lvCount}'
                  ' · 容量 ${vg.size} · 空闲 ${vg.free}',
              busy: _isBusy('vg:${vg.name}'),
              actions: [
                _dangerAction(
                  tooltip: '删除卷组 ${vg.name}',
                  onPressed: () => _startFlow(() => _removeVg(vg)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _lvCard(LvmInfo lvm) {
    final theme = Theme.of(context);
    return SectionCard(
      title: '逻辑卷（${lvm.lvs.length}）',
      trailing: _isBusy('lv:create')
          ? const BusyIndicator()
          : TextButton.icon(
              onPressed:
                  _locked ? null : () => _startFlow(() => _createLv(lvm)),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('创建'),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (lvm.lvs.isEmpty)
            Text(
              '暂无逻辑卷',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          for (final lv in lvm.lvs)
            _itemRow(
              icon: Icons.layers_outlined,
              title: lv.name,
              subtitle: '卷组 ${lv.vgName} · 容量 ${lv.size}\n${lv.path}',
              busy: _isBusy('lv:${lv.path}'),
              actions: [
                A11yIconButton(
                  tooltip: '扩容逻辑卷 ${lv.name}',
                  icon: const Icon(Icons.open_in_full, size: 18),
                  onPressed:
                      _locked ? null : () => _startFlow(() => _extendLv(lv)),
                ),
                _dangerAction(
                  tooltip: '删除逻辑卷 ${lv.name}',
                  onPressed: () => _startFlow(() => _removeLv(lv)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _dangerAction({
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return A11yIconButton(
      tooltip: tooltip,
      icon: Icon(
        Icons.delete_outline,
        size: 18,
        color: _locked ? null : Theme.of(context).colorScheme.error,
      ),
      onPressed: _locked ? null : onPressed,
    );
  }

  Widget _itemRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool busy,
    required List<Widget> actions,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
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
            ...actions,
        ],
      ),
    );
  }
}
