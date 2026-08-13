import 'json_utils.dart';

/// `GET /api/toolbox_disk/smart/disks` 的响应。
///
/// 未安装 smartmontools 时 `available` 为 false，`message` 为面板给出的安装提示。
class SmartDiskList {
  const SmartDiskList({
    required this.available,
    required this.message,
    required this.disks,
  });

  final bool available;
  final String message;
  final List<SmartDisk> disks;

  factory SmartDiskList.fromJson(dynamic data) {
    final root = jsonMap(data);
    return SmartDiskList(
      available: jsonBool(root['available']),
      message: jsonString(root['message']),
      disks: jsonMapList(root['disks']).map(SmartDisk.fromJson).toList(),
    );
  }
}

/// 支持 SMART 的磁盘。
class SmartDisk {
  const SmartDisk({
    required this.name,
    required this.model,
    required this.type,
  });

  /// 设备名（不含 `/dev/` 前缀）。
  final String name;
  final String model;

  /// smartctl 识别的设备类型，如 `sat`、`nvme`。
  final String type;

  String get label => model.isEmpty ? name : '$name（$model）';

  factory SmartDisk.fromJson(Map<String, dynamic> json) => SmartDisk(
    name: jsonString(json['name']),
    model: jsonString(json['model']),
    type: jsonString(json['type']),
  );
}

/// 一条 SMART 属性（ATA 属性表 / NVMe 健康日志统一成同一结构展示）。
class SmartAttribute {
  const SmartAttribute({
    required this.id,
    required this.name,
    required this.value,
    required this.worst,
    required this.threshold,
    required this.raw,
    required this.whenFailed,
  });

  /// ATA 属性 ID；NVMe 无 ID 时为空。
  final String id;
  final String name;

  /// 归一化当前值（NVMe 行直接放展示值，此时 [worst] / [threshold] 为空）。
  final String value;
  final String worst;
  final String threshold;
  final String raw;

  /// 非空表示该属性曾经失败。
  final String whenFailed;

  bool get failed => whenFailed.isNotEmpty;
}

/// `GET /api/toolbox_disk/smart/info` 的响应（smartctl -j -a 的原始 JSON）。
class SmartInfo {
  const SmartInfo({
    required this.modelName,
    required this.serialNumber,
    required this.firmware,
    required this.capacityBytes,
    required this.interfaceName,
    required this.rotationRate,
    required this.powerOnHours,
    required this.powerCycleCount,
    required this.temperature,
    required this.healthPassed,
    required this.deviceTime,
    required this.isNvme,
    required this.attributes,
    required this.messages,
  });

  final String modelName;
  final String serialNumber;
  final String firmware;
  final int capacityBytes;
  final String interfaceName;

  /// 转速；0 表示固态硬盘，null 表示未知。
  final num? rotationRate;
  final num? powerOnHours;
  final num? powerCycleCount;

  /// 当前温度（摄氏度），未知为 null。
  final num? temperature;

  /// SMART 总体健康结论；null 表示设备未返回该字段。
  final bool? healthPassed;

  /// smartctl 输出的设备本地时间文本（面板侧已是服务器本地时间）。
  final String deviceTime;

  final bool isNvme;
  final List<SmartAttribute> attributes;

  /// smartctl 的提示 / 错误信息（如设备不支持 SMART）。
  final List<String> messages;

  /// 转速展示文案。
  String get rotationLabel {
    final rate = rotationRate;
    if (rate == null) return '';
    if (rate == 0) return '固态硬盘（SSD）';
    return '${rate.toStringAsFixed(0)} RPM';
  }

  factory SmartInfo.fromJson(dynamic data) {
    final root = jsonMap(data);
    final nvmeLog = jsonMap(root['nvme_smart_health_information_log']);
    final isNvme = nvmeLog.isNotEmpty;

    num? temperature = jsonNumOrNull(jsonMap(root['temperature'])['current']);
    temperature ??= jsonNumOrNull(nvmeLog['temperature']);

    final attributes = <SmartAttribute>[];
    if (isNvme) {
      for (final entry in _nvmeFields) {
        final value = nvmeLog[entry.key];
        if (value == null) continue;
        attributes.add(
          SmartAttribute(
            id: '',
            name: entry.label,
            value: '${jsonString(value)}${entry.unit}',
            worst: '',
            threshold: '',
            raw: '',
            whenFailed: '',
          ),
        );
      }
    } else {
      final table = jsonMapList(jsonMap(root['ata_smart_attributes'])['table']);
      for (final row in table) {
        final rawMap = jsonMap(row['raw']);
        final rawText = jsonString(rawMap['string']).isNotEmpty
            ? jsonString(rawMap['string'])
            : jsonString(rawMap['value']);
        attributes.add(
          SmartAttribute(
            id: jsonString(row['id']),
            name: jsonString(row['name']),
            value: jsonString(row['value']),
            worst: jsonString(row['worst']),
            threshold: jsonString(row['thresh']),
            raw: rawText,
            whenFailed: jsonString(row['when_failed']),
          ),
        );
      }
    }

    final messages = <String>[];
    for (final item in jsonMapList(jsonMap(root['smartctl'])['messages'])) {
      final text = jsonString(item['string']);
      if (text.isNotEmpty) messages.add(text);
    }

    return SmartInfo(
      modelName: jsonString(root['model_name']),
      serialNumber: jsonString(root['serial_number']),
      firmware: jsonString(root['firmware_version']),
      capacityBytes: jsonInt(jsonMap(root['user_capacity'])['bytes']),
      interfaceName: jsonString(jsonMap(root['device'])['type']).isNotEmpty
          ? jsonString(jsonMap(root['device'])['type'])
          : jsonString(jsonMap(root['device_type'])['name']),
      rotationRate: jsonNumOrNull(root['rotation_rate']),
      powerOnHours: jsonNumOrNull(jsonMap(root['power_on_time'])['hours']),
      powerCycleCount: jsonNumOrNull(root['power_cycle_count']),
      temperature: temperature,
      healthPassed: jsonBoolOrNull(jsonMap(root['smart_status'])['passed']),
      deviceTime: jsonString(jsonMap(root['local_time'])['asctime']),
      isNvme: isNvme,
      attributes: attributes,
      messages: messages,
    );
  }
}

/// NVMe 健康日志的字段映射（与面板 Web 端 SmartView.vue 保持一致）。
const List<({String key, String label, String unit})> _nvmeFields = [
  (key: 'critical_warning', label: '严重警告', unit: ''),
  (key: 'temperature', label: '温度', unit: ' °C'),
  (key: 'available_spare', label: '可用备用块', unit: '%'),
  (key: 'available_spare_threshold', label: '备用块阈值', unit: '%'),
  (key: 'percentage_used', label: '寿命消耗', unit: '%'),
  (key: 'data_units_read', label: '读取数据单元', unit: ''),
  (key: 'data_units_written', label: '写入数据单元', unit: ''),
  (key: 'host_reads', label: '主机读命令数', unit: ''),
  (key: 'host_writes', label: '主机写命令数', unit: ''),
  (key: 'controller_busy_time', label: '控制器繁忙时间', unit: ' 分钟'),
  (key: 'power_cycles', label: '通电次数', unit: ''),
  (key: 'power_on_hours', label: '通电时长', unit: ' 小时'),
  (key: 'unsafe_shutdowns', label: '异常断电次数', unit: ''),
  (key: 'media_errors', label: '介质错误', unit: ''),
  (key: 'num_err_log_entries', label: '错误日志条数', unit: ''),
];
