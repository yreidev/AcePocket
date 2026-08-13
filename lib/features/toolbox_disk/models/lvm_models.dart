import 'json_utils.dart';

/// LVM 信息（`GET /api/toolbox_disk/lvm`）。
///
/// 面板把 `pvdisplay/vgdisplay/lvdisplay -C --noheadings --separator '|'` 的
/// 每一行按 `|` 切分成 `field_0`、`field_1`… 返回（见 service 的 `parseLVMOutput`），
/// 字段顺序由命令的 `-o` 参数决定：
/// - pv：pv_name | vg_name | pv_size | pv_free
/// - vg：vg_name | pv_count | lv_count | vg_size | vg_free
/// - lv：lv_name | vg_name | lv_size | lv_path
class LvmInfo {
  const LvmInfo({required this.pvs, required this.vgs, required this.lvs});

  final List<PhysicalVolume> pvs;
  final List<VolumeGroup> vgs;
  final List<LogicalVolume> lvs;

  bool get isEmpty => pvs.isEmpty && vgs.isEmpty && lvs.isEmpty;

  /// 尚未加入卷组的物理卷（可用于创建卷组）。
  List<PhysicalVolume> get freePvs =>
      pvs.where((pv) => pv.vgName.isEmpty).toList();

  factory LvmInfo.fromJson(dynamic data) {
    final root = jsonMap(data);
    return LvmInfo(
      pvs: _parse(root['pvs'], 4, PhysicalVolume._fromFields),
      vgs: _parse(root['vgs'], 5, VolumeGroup._fromFields),
      lvs: _parse(root['lvs'], 4, LogicalVolume._fromFields),
    );
  }

  /// 解析 `field_N` 形式的行。
  ///
  /// 未安装 LVM 工具时命令输出可能是 `xxx: command not found` 之类的单字段文本，
  /// 这里按「字段数不足即丢弃」过滤，避免把报错文本当成卷展示。
  static List<T> _parse<T>(
    dynamic raw,
    int expected,
    T Function(List<String>) builder,
  ) {
    final result = <T>[];
    for (final row in jsonMapList(raw)) {
      final fields = <String>[];
      for (var i = 0; i < expected; i++) {
        fields.add(jsonString(row['field_$i']));
      }
      // 有效行至少要能切出 2 个字段（说明确实带有 `|` 分隔符）。
      if (row.length < 2 || fields.first.isEmpty) continue;
      result.add(builder(fields));
    }
    return result;
  }
}

/// 物理卷。
class PhysicalVolume {
  const PhysicalVolume({
    required this.name,
    required this.vgName,
    required this.size,
    required this.free,
  });

  /// 设备绝对路径，如 `/dev/sdb1`（删除物理卷时原样回传）。
  final String name;

  /// 所属卷组，为空表示未加入任何卷组。
  final String vgName;

  /// LVM 原样输出的容量文本，如 `<8.00g`。
  final String size;
  final String free;

  static PhysicalVolume _fromFields(List<String> f) =>
      PhysicalVolume(name: f[0], vgName: f[1], size: f[2], free: f[3]);
}

/// 卷组。
class VolumeGroup {
  const VolumeGroup({
    required this.name,
    required this.pvCount,
    required this.lvCount,
    required this.size,
    required this.free,
  });

  final String name;
  final String pvCount;
  final String lvCount;
  final String size;
  final String free;

  static VolumeGroup _fromFields(List<String> f) => VolumeGroup(
    name: f[0],
    pvCount: f[1],
    lvCount: f[2],
    size: f[3],
    free: f[4],
  );
}

/// 逻辑卷。
class LogicalVolume {
  const LogicalVolume({
    required this.name,
    required this.vgName,
    required this.size,
    required this.path,
  });

  final String name;
  final String vgName;
  final String size;

  /// 逻辑卷设备路径，如 `/dev/vg0/data`（删除 / 扩容时使用）。
  final String path;

  static LogicalVolume _fromFields(List<String> f) =>
      LogicalVolume(name: f[0], vgName: f[1], size: f[2], path: f[3]);
}
