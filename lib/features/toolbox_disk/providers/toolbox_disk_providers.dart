import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/storage/server_store.dart';
import '../models/disk_models.dart';
import '../models/lvm_models.dart';
import '../models/raid_models.dart';
import '../models/smart_models.dart';
import '../repo/toolbox_disk_repo.dart';

/// 磁盘工具箱数据仓库。
final toolboxDiskRepoProvider = Provider<ToolboxDiskRepository>(
  (ref) => ToolboxDiskRepository(ref.watch(apiClientProvider)),
);

/// 磁盘与分区列表（lsblk + df）。
///
/// 面板的磁盘接口一次性返回全部块设备，没有分页参数，因此列表页只做下拉刷新。
final diskListProvider = FutureProvider.autoDispose<DiskListData>(
  (ref) => ref.watch(toolboxDiskRepoProvider).list(),
);

/// `/etc/fstab` 条目列表。
final fstabProvider = FutureProvider.autoDispose<List<FstabEntry>>(
  (ref) => ref.watch(toolboxDiskRepoProvider).fstab(),
);

/// LVM 信息（PV / VG / LV）。
final lvmInfoProvider = FutureProvider.autoDispose<LvmInfo>(
  (ref) => ref.watch(toolboxDiskRepoProvider).lvm(),
);

/// 支持 SMART 的磁盘列表。
final smartDisksProvider = FutureProvider.autoDispose<SmartDiskList>(
  (ref) => ref.watch(toolboxDiskRepoProvider).smartDisks(),
);

/// SMART 页当前选中的磁盘（null 表示尚未选择，进入页面后自动选中第一块）。
final selectedSmartDiskProvider = StateProvider.autoDispose<String?>(
  (ref) => null,
);

/// 指定磁盘的 SMART 详情。
final smartInfoProvider = FutureProvider.autoDispose.family<SmartInfo, String>(
  (ref, device) => ref.watch(toolboxDiskRepoProvider).smartInfo(device),
);

/// RAID 阵列状态。
final raidInfoProvider = FutureProvider.autoDispose<RaidInfo>(
  (ref) => ref.watch(toolboxDiskRepoProvider).raid(),
);
