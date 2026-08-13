import 'json_utils.dart';

/// `lsblk -J -b -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,UUID,LABEL,MODEL` 的块设备节点。
///
/// 对应面板 `internal/service/toolbox_disk.go` 的 `List` / `GetPartitions`：
/// 面板原样透传 lsblk 的 `blockdevices` 数组。
class BlockDevice {
  const BlockDevice({
    required this.name,
    required this.size,
    required this.type,
    required this.mountpoint,
    required this.fstype,
    required this.uuid,
    required this.label,
    required this.model,
    required this.children,
  });

  /// 设备名（不含 `/dev/` 前缀），如 `sda`、`sda1`、`nvme0n1p1`。
  final String name;

  /// 容量（字节）。
  final int size;

  /// 设备类型：`disk` / `part` / `lvm` / `crypt` / `rom` / `loop` …
  final String type;

  /// 挂载点，未挂载为空字符串。
  final String mountpoint;

  /// 文件系统类型，未格式化为空字符串。
  final String fstype;
  final String uuid;
  final String label;

  /// 磁盘型号（仅 `disk` 有值）。
  final String model;

  final List<BlockDevice> children;

  factory BlockDevice.fromJson(Map<String, dynamic> json) {
    // 新版 util-linux 用 mountpoints 数组，旧版用 mountpoint 字符串，两者都兼容。
    var mountpoint = jsonString(json['mountpoint']);
    if (mountpoint.isEmpty && json['mountpoints'] is List) {
      final list = (json['mountpoints'] as List)
          .map(jsonString)
          .where((e) => e.isNotEmpty)
          .toList();
      if (list.isNotEmpty) mountpoint = list.first;
    }
    return BlockDevice(
      name: jsonString(json['name']),
      size: jsonInt(json['size']),
      type: jsonString(json['type']),
      mountpoint: mountpoint,
      fstype: jsonString(json['fstype']),
      uuid: jsonString(json['uuid']),
      label: jsonString(json['label']),
      model: jsonString(json['model']),
      children: jsonMapList(
        json['children'],
      ).map(BlockDevice.fromJson).toList(),
    );
  }

  /// 自身或任意子设备是否挂载在根目录（用于判定系统盘）。
  bool get containsRoot {
    if (mountpoint == '/') return true;
    return children.any((child) => child.containsRoot);
  }
}

/// `df -B1` 的单条使用量信息（面板以挂载点为键返回）。
class DfInfo {
  const DfInfo({
    required this.size,
    required this.used,
    required this.avail,
    required this.percent,
  });

  final int size;
  final int used;
  final int avail;

  /// 已用百分比（0-100）。
  final int percent;

  factory DfInfo.fromJson(Map<String, dynamic> json) => DfInfo(
    size: jsonInt(json['size']),
    used: jsonInt(json['used']),
    avail: jsonInt(json['avail']),
    percent: jsonInt(json['percent']),
  );
}

/// 展平后的分区 / 逻辑卷条目（磁盘卡片中的一行）。
class PartitionInfo {
  const PartitionInfo({
    required this.name,
    required this.size,
    required this.type,
    required this.mountpoint,
    required this.fstype,
    required this.uuid,
    required this.label,
    required this.depth,
    required this.used,
    required this.avail,
    required this.percent,
    required this.onSystemDisk,
  });

  final String name;
  final int size;
  final String type;
  final String mountpoint;
  final String fstype;
  final String uuid;
  final String label;

  /// 嵌套层级（0 为磁盘的直接子设备，1 为 LVM / 加密卷等再下一层）。
  final int depth;

  final int used;
  final int avail;
  final int percent;

  /// 所属磁盘是否为系统盘。
  final bool onSystemDisk;

  bool get mounted => mountpoint.isNotEmpty;

  /// 是否为根分区（禁止卸载 / 格式化）。
  bool get isRoot => mountpoint == '/';

  /// 设备绝对路径。
  String get devicePath => '/dev/$name';
}

/// 一块物理磁盘及其分区。
class DiskInfo {
  const DiskInfo({
    required this.name,
    required this.size,
    required this.type,
    required this.model,
    required this.mountpoint,
    required this.fstype,
    required this.isSystemDisk,
    required this.partitions,
  });

  final String name;
  final int size;
  final String type;
  final String model;

  /// 整盘直接挂载时的挂载点（无分区表的场景）。
  final String mountpoint;
  final String fstype;

  final bool isSystemDisk;
  final List<PartitionInfo> partitions;

  String get devicePath => '/dev/$name';

  /// 型号展示文案（与面板 Web 端一致：识别不到型号时显示「未知」）。
  String get modelLabel {
    if (model.isEmpty) return '未知型号';
    final lower = model.toLowerCase();
    if (lower.contains('ssd') || lower.contains('nvme')) return 'SSD · $model';
    return model;
  }
}

/// `GET /api/toolbox_disk/list` 的解析结果。
class DiskListData {
  const DiskListData({required this.disks, required this.df});

  final List<DiskInfo> disks;

  /// 挂载点 -> 使用量。
  final Map<String, DfInfo> df;

  /// 全部未挂载、可作为挂载 / 格式化目标的分区（含 LVM 逻辑卷）。
  List<PartitionInfo> get unmountedPartitions => [
    for (final disk in disks)
      for (final part in disk.partitions)
        if (!part.mounted) part,
  ];

  /// 可用于创建物理卷的设备：非系统盘的整盘（无分区）或未挂载分区。
  List<({String device, int size})> get pvCandidates {
    final result = <({String device, int size})>[];
    for (final disk in disks) {
      if (disk.isSystemDisk) continue;
      if (disk.partitions.isEmpty && disk.mountpoint.isEmpty) {
        result.add((device: disk.name, size: disk.size));
      }
      for (final part in disk.partitions) {
        if (!part.mounted && part.type == 'part') {
          result.add((device: part.name, size: part.size));
        }
      }
    }
    return result;
  }

  factory DiskListData.fromJson(dynamic data) {
    final root = jsonMap(data);
    final df = <String, DfInfo>{};
    jsonMap(root['df']).forEach((key, value) {
      df[key] = DfInfo.fromJson(jsonMap(value));
    });

    final disks = <DiskInfo>[];
    for (final raw in jsonMapList(root['disks'])) {
      final device = BlockDevice.fromJson(raw);
      // 只展示物理磁盘；loop / rom 等虚拟设备不参与磁盘管理。
      if (device.type != 'disk') continue;
      final isSystemDisk = device.containsRoot;
      final partitions = <PartitionInfo>[];

      void walk(List<BlockDevice> children, int depth) {
        for (final child in children) {
          final usage = df[child.mountpoint];
          partitions.add(
            PartitionInfo(
              name: child.name,
              size: child.size,
              type: child.type,
              mountpoint: child.mountpoint,
              fstype: child.fstype,
              uuid: child.uuid,
              label: child.label,
              depth: depth,
              used: usage?.used ?? 0,
              avail: usage?.avail ?? 0,
              percent: usage?.percent ?? 0,
              onSystemDisk: isSystemDisk,
            ),
          );
          walk(child.children, depth + 1);
        }
      }

      walk(device.children, 0);
      disks.add(
        DiskInfo(
          name: device.name,
          size: device.size,
          type: device.type,
          model: device.model,
          mountpoint: device.mountpoint,
          fstype: device.fstype,
          isSystemDisk: isSystemDisk,
          partitions: partitions,
        ),
      );
    }

    return DiskListData(disks: disks, df: df);
  }
}

/// `/etc/fstab` 条目（`internal/request/toolbox_disk.go` 的 ToolboxDiskFstabEntry）。
class FstabEntry {
  const FstabEntry({
    required this.device,
    required this.mountPoint,
    required this.fsType,
    required this.options,
    required this.dump,
    required this.pass,
  });

  /// 设备（`UUID=xxx` 或 `/dev/xxx`）。
  final String device;
  final String mountPoint;
  final String fsType;
  final String options;
  final String dump;
  final String pass;

  /// 根挂载点不允许删除（面板侧同样会拒绝）。
  bool get isRoot => mountPoint == '/';

  factory FstabEntry.fromJson(Map<String, dynamic> json) => FstabEntry(
    device: jsonString(json['device']),
    mountPoint: jsonString(json['mount_point']),
    fsType: jsonString(json['fs_type']),
    options: jsonString(json['options']),
    dump: jsonString(json['dump']),
    pass: jsonString(json['pass']),
  );
}

/// 面板支持的文件系统类型（`request.ToolboxDiskFormat` 的 `in:ext4,ext3,xfs,btrfs`）。
const List<String> kFsTypes = <String>['ext4', 'ext3', 'xfs', 'btrfs'];
