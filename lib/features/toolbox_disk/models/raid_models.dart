import 'json_utils.dart';

/// `GET /api/toolbox_disk/raid/info` 的响应。
///
/// 面板按 mdadm → MegaRAID → HP Smart Array → Adaptec 的顺序探测，
/// 都没有时返回 `available = false`。
class RaidInfo {
  const RaidInfo({
    required this.available,
    required this.message,
    required this.type,
    required this.controllers,
    required this.arrays,
  });

  final bool available;
  final String message;

  /// `mdadm` / `megaraid` / `hpsa` / `adaptec`。
  final String type;

  final List<RaidController> controllers;
  final List<RaidArray> arrays;

  /// RAID 类型的中文展示名。
  String get typeLabel {
    switch (type) {
      case 'mdadm':
        return 'Linux 软 RAID（mdadm）';
      case 'megaraid':
        return 'MegaRAID（LSI / Broadcom）';
      case 'hpsa':
        return 'HP Smart Array';
      case 'adaptec':
        return 'Adaptec';
      default:
        return type.isEmpty ? '未知' : type;
    }
  }

  factory RaidInfo.fromJson(dynamic data) {
    final root = jsonMap(data);
    return RaidInfo(
      available: jsonBool(root['available']),
      message: jsonString(root['message']),
      type: jsonString(root['type']),
      controllers: jsonMapList(root['controllers'])
          .map(RaidController.fromJson)
          .toList(),
      arrays: jsonMapList(root['arrays']).map(RaidArray.fromJson).toList(),
    );
  }
}

/// RAID 控制器。
class RaidController {
  const RaidController({
    required this.model,
    required this.serial,
    required this.firmware,
    required this.cacheSize,
  });

  final String model;
  final String serial;
  final String firmware;
  final String cacheSize;

  factory RaidController.fromJson(Map<String, dynamic> json) => RaidController(
        model: jsonString(json['model']),
        serial: jsonString(json['serial']),
        firmware: jsonString(json['firmware']),
        cacheSize: jsonString(json['cache_size']),
      );
}

/// RAID 阵列。
class RaidArray {
  const RaidArray({
    required this.name,
    required this.raidLevel,
    required this.size,
    required this.state,
    required this.stripSize,
    required this.activeDevices,
    required this.totalDevices,
    required this.rebuildPct,
    required this.devices,
  });

  final String name;
  final String raidLevel;
  final String size;
  final String state;
  final String stripSize;
  final int activeDevices;
  final int totalDevices;

  /// 重建进度文本（仅重建中有值）。
  final String rebuildPct;

  final List<RaidDevice> devices;

  factory RaidArray.fromJson(Map<String, dynamic> json) => RaidArray(
        name: jsonString(json['name']),
        raidLevel: jsonString(json['raid_level']),
        size: jsonString(json['size']),
        state: jsonString(json['state']),
        stripSize: jsonString(json['strip_size']),
        activeDevices: jsonInt(json['active_devices']),
        totalDevices: jsonInt(json['total_devices']),
        rebuildPct: jsonString(json['rebuild_pct']),
        devices: jsonMapList(json['devices']).map(RaidDevice.fromJson).toList(),
      );
}

/// RAID 成员磁盘。
class RaidDevice {
  const RaidDevice({
    required this.name,
    required this.slot,
    required this.size,
    required this.state,
    required this.model,
    required this.serial,
  });

  final String name;
  final String slot;
  final String size;
  final String state;
  final String model;
  final String serial;

  factory RaidDevice.fromJson(Map<String, dynamic> json) => RaidDevice(
        name: jsonString(json['name']),
        slot: jsonString(json['slot']),
        size: jsonString(json['size']),
        state: jsonString(json['state']),
        model: jsonString(json['model']),
        serial: jsonString(json['serial']),
      );
}

/// 阵列 / 磁盘状态的健康等级（用于选择展示颜色）。
enum RaidHealth { good, warning, bad, unknown }

/// 状态文案的健康判定（关键字与面板 Web 端 RaidView.vue 的 `getStateType` 一致）。
///
/// 与 Web 端的差别：这里先判异常再判正常。mdadm 的状态常是
/// `clean, degraded` 这类组合值，先匹配 `clean` 会把降级阵列误判为正常。
RaidHealth raidHealthOf(String state) {
  if (state.isEmpty) return RaidHealth.unknown;
  final s = state.toLowerCase();
  if (s.contains('fail') || s.contains('offline') || s.contains('error')) {
    return RaidHealth.bad;
  }
  if (s.contains('degrad') || s.contains('rebuild') || s.contains('recover')) {
    return RaidHealth.warning;
  }
  if (s.contains('clean') ||
      s.contains('active') ||
      s.contains('optimal') ||
      s == 'ok') {
    return RaidHealth.good;
  }
  return RaidHealth.unknown;
}
