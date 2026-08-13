import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/version/panel_feature.dart';
import '../../../core/widgets/a11y.dart';
import '../../../core/widgets/feature_gate.dart';
import '../providers/toolbox_disk_providers.dart';
import '../widgets/disk_tab.dart';
import '../widgets/fstab_tab.dart';
import '../widgets/lvm_tab.dart';

/// 磁盘工具箱主页面（`/toolbox/disk`）。
///
/// 三个标签页：
/// - 磁盘：磁盘 / 分区列表，挂载、卸载、格式化、初始化；
/// - LVM：物理卷 / 卷组 / 逻辑卷的创建、删除与扩容；
/// - 自动挂载：`/etc/fstab` 条目管理。
///
/// SMART 健康与 RAID 阵列在右上角菜单进入独立页面。
class DiskPage extends ConsumerStatefulWidget {
  const DiskPage({super.key});

  @override
  ConsumerState<DiskPage> createState() => _DiskPageState();
}

class _DiskPageState extends ConsumerState<DiskPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 3,
    vsync: this,
  );

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _refreshCurrent() {
    switch (_tabController.index) {
      case 0:
        ref.invalidate(diskListProvider);
      case 1:
        ref.invalidate(lvmInfoProvider);
        ref.invalidate(diskListProvider);
      case 2:
        ref.invalidate(fstabProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('磁盘管理'),
        actions: [
          A11yIconButton(
            tooltip: '刷新当前标签页',
            icon: const Icon(Icons.refresh),
            onPressed: _refreshCurrent,
          ),
          PopupMenuButton<String>(
            tooltip: '更多磁盘工具',
            onSelected: (value) {
              switch (value) {
                case 'smart':
                  context.push('/toolbox/disk/smart');
                case 'raid':
                  context.push('/toolbox/disk/raid');
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem<String>(
                value: 'smart',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(Icons.monitor_heart_outlined),
                  title: Text('SMART 健康'),
                ),
              ),
              PopupMenuItem<String>(
                value: 'raid',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(Icons.grid_view_rounded),
                  title: Text('RAID 阵列'),
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '磁盘'),
            Tab(text: 'LVM'),
            Tab(text: '自动挂载'),
          ],
        ),
      ),
      body: Column(
        children: [
          const FeatureUnsupportedBanner(feature: PanelFeature.toolboxDisk),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [DiskTab(), LvmTab(), FstabTab()],
            ),
          ),
        ],
      ),
    );
  }
}
