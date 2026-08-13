import 'dart:convert';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../models/disk_models.dart';
import '../models/json_utils.dart';
import '../models/lvm_models.dart';
import '../models/raid_models.dart';
import '../models/smart_models.dart';

/// 磁盘工具箱数据仓库。
///
/// 接口路径、方法与字段名以面板源码 `internal/route/toolbox_disk.go`、
/// `internal/request/toolbox_disk.go`、`internal/service/toolbox_disk.go` 为准：
///
/// | 方法 | 路径 |
/// | --- | --- |
/// | GET    | `/toolbox_disk/list` |
/// | POST   | `/toolbox_disk/partitions` |
/// | POST   | `/toolbox_disk/mount` |
/// | POST   | `/toolbox_disk/umount` |
/// | POST   | `/toolbox_disk/format` |
/// | POST   | `/toolbox_disk/init` |
/// | GET    | `/toolbox_disk/fstab` |
/// | DELETE | `/toolbox_disk/fstab` |
/// | GET    | `/toolbox_disk/lvm` |
/// | POST   | `/toolbox_disk/lvm/pv` |
/// | DELETE | `/toolbox_disk/lvm/pv` |
/// | POST   | `/toolbox_disk/lvm/vg` |
/// | DELETE | `/toolbox_disk/lvm/vg` |
/// | POST   | `/toolbox_disk/lvm/lv` |
/// | DELETE | `/toolbox_disk/lvm/lv` |
/// | POST   | `/toolbox_disk/lvm/lv/extend` |
/// | GET    | `/toolbox_disk/smart/disks` |
/// | GET    | `/toolbox_disk/smart/info` |
/// | GET    | `/toolbox_disk/raid/info` |
class ToolboxDiskRepository {
  const ToolboxDiskRepository(this._api);

  final ApiClient _api;

  // ------------------------------------------------------------------ 磁盘

  /// 磁盘与分区列表（lsblk + df）。
  Future<DiskListData> list() async {
    final data = await _api.get('/toolbox_disk/list');
    return DiskListData.fromJson(data);
  }

  /// 指定磁盘的分区详情。
  ///
  /// 面板直接把 `lsblk -J` 的**原始文本**作为 data 返回，因此这里需要再解析一次
  /// （容错：个别版本可能已是 JSON 对象）。
  Future<List<BlockDevice>> partitions(String device) async {
    final data = await _api.post(
      '/toolbox_disk/partitions',
      body: {'device': device},
    );
    dynamic decoded = data;
    if (data is String) {
      final text = data.trim();
      if (text.isEmpty) return const <BlockDevice>[];
      try {
        decoded = jsonDecode(text);
      } catch (_) {
        throw ApiException('无法解析面板返回的分区信息');
      }
    }
    return jsonMapList(jsonMap(decoded)['blockdevices'])
        .map(BlockDevice.fromJson)
        .toList();
  }

  /// 挂载分区。[device] 不含 `/dev/` 前缀。
  ///
  /// [writeFstab] 为 true 时面板会把 `UUID=xxx <path> <fstype> <option> 0 2`
  /// 追加进 `/etc/fstab` 实现开机自动挂载。
  Future<void> mount({
    required String device,
    required String path,
    bool writeFstab = false,
    String mountOption = '',
  }) =>
      _api.post('/toolbox_disk/mount', body: {
        'device': device,
        'path': path,
        'write_fstab': writeFstab,
        'mount_option': mountOption,
      });

  /// 卸载挂载点。
  Future<void> umount(String path) =>
      _api.post('/toolbox_disk/umount', body: {'path': path});

  /// 格式化分区（破坏性操作，分区数据全部丢失）。
  Future<void> format({required String device, required String fsType}) =>
      _api.post('/toolbox_disk/format', body: {
        'device': device,
        'fs_type': fsType,
      });

  /// 初始化磁盘：清除分区表 → 新建单个分区 → 格式化（破坏性操作）。
  Future<void> init({required String device, required String fsType}) =>
      _api.post('/toolbox_disk/init', body: {
        'device': device,
        'fs_type': fsType,
      });

  // ------------------------------------------------------------------ fstab

  /// `/etc/fstab` 条目列表。
  Future<List<FstabEntry>> fstab() async {
    final data = await _api.get('/toolbox_disk/fstab');
    if (data is! List) return const <FstabEntry>[];
    return data
        .whereType<Map>()
        .map((e) => FstabEntry.fromJson(jsonMap(e)))
        .toList();
  }

  /// 删除 fstab 条目（面板随后会执行 `mount -a` 重新挂载）。
  Future<void> deleteFstab(String mountPoint) =>
      _api.delete('/toolbox_disk/fstab', body: {'mount_point': mountPoint});

  // ------------------------------------------------------------------ LVM

  /// 物理卷 / 卷组 / 逻辑卷信息。
  Future<LvmInfo> lvm() async {
    final data = await _api.get('/toolbox_disk/lvm');
    return LvmInfo.fromJson(data);
  }

  /// 创建物理卷。[device] 为不含 `/dev/` 前缀的设备名（面板会自行拼接）。
  Future<void> createPv(String device) =>
      _api.post('/toolbox_disk/lvm/pv', body: {'device': device});

  /// 删除物理卷。[device] 为 `pvdisplay` 输出的**完整路径**（如 `/dev/sdb1`）。
  Future<void> removePv(String device) =>
      _api.delete('/toolbox_disk/lvm/pv', body: {'device': device});

  /// 创建卷组。[devices] 为物理卷的完整路径列表。
  Future<void> createVg(
          {required String name, required List<String> devices}) =>
      _api.post('/toolbox_disk/lvm/vg', body: {
        'name': name,
        'devices': devices,
      });

  /// 删除卷组（`vgremove -f`，组内逻辑卷会一并删除）。
  Future<void> removeVg(String name) =>
      _api.delete('/toolbox_disk/lvm/vg', body: {'name': name});

  /// 创建逻辑卷，[sizeGb] 单位 GB。
  Future<void> createLv({
    required String name,
    required String vgName,
    required int sizeGb,
  }) =>
      _api.post('/toolbox_disk/lvm/lv', body: {
        'name': name,
        'vg_name': vgName,
        'size': sizeGb,
      });

  /// 删除逻辑卷（`lvremove -f`，卷上数据全部丢失）。
  Future<void> removeLv(String path) =>
      _api.delete('/toolbox_disk/lvm/lv', body: {'path': path});

  /// 扩容逻辑卷，[sizeGb] 为**增加**的容量（GB）。
  ///
  /// [resize] 为 true 时面板会同步扩展文件系统
  /// （ext3/ext4 用 resize2fs；xfs / btrfs 必须已挂载，否则接口报错）。
  Future<void> extendLv({
    required String path,
    required int sizeGb,
    required bool resize,
  }) =>
      _api.post('/toolbox_disk/lvm/lv/extend', body: {
        'path': path,
        'size': sizeGb,
        'resize': resize,
      });

  // ------------------------------------------------------------------ 健康

  /// 支持 SMART 的磁盘列表。
  Future<SmartDiskList> smartDisks() async {
    final data = await _api.get('/toolbox_disk/smart/disks');
    return SmartDiskList.fromJson(data);
  }

  /// 指定磁盘的 SMART 详情（device 通过 query 传递）。
  Future<SmartInfo> smartInfo(String device) async {
    final data =
        await _api.get('/toolbox_disk/smart/info', query: {'device': device});
    return SmartInfo.fromJson(data);
  }

  /// RAID 阵列状态。
  Future<RaidInfo> raid() async {
    final data = await _api.get('/toolbox_disk/raid/info');
    return RaidInfo.fromJson(data);
  }
}
