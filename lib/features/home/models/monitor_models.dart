/// 监控模块模型。
///
/// 字段以面板源码为准：
/// - `internal/request/monitor.go` MonitorSetting / MonitorList
/// - `pkg/types/monitor.go` MonitorDetail 及其子类型
/// - `internal/service/monitor.go` List（数值序列多为 "12.34" 形式的字符串）
library;

double _d(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

List<double> _dList(dynamic v) =>
    v is List ? v.map(_d).toList() : const <double>[];

/// `GET/POST /monitor/setting` 的监控设置。
class MonitorSetting {
  const MonitorSetting({
    required this.enabled,
    required this.days,
    required this.interval,
    required this.alertDays,
  });

  /// 是否启用监控。
  final bool enabled;

  /// 监控数据保留天数。
  final int days;

  /// 采集间隔（分钟，1-120）。
  final int interval;

  /// 告警记录保留天数（1-365）。
  final int alertDays;

  factory MonitorSetting.fromJson(Map<String, dynamic> json) {
    return MonitorSetting(
      enabled: json['enabled'] as bool? ?? false,
      days: (json['days'] as num?)?.toInt() ?? 30,
      interval: (json['interval'] as num?)?.toInt() ?? 1,
      alertDays: (json['alert_days'] as num?)?.toInt() ?? 30,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'days': days,
        'interval': interval,
        'alert_days': alertDays,
      };

  MonitorSetting copyWith({
    bool? enabled,
    int? days,
    int? interval,
    int? alertDays,
  }) {
    return MonitorSetting(
      enabled: enabled ?? this.enabled,
      days: days ?? this.days,
      interval: interval ?? this.interval,
      alertDays: alertDays ?? this.alertDays,
    );
  }
}

/// 负载历史序列。
class LoadSeries {
  const LoadSeries({
    required this.load1,
    required this.load5,
    required this.load15,
  });

  final List<double> load1;
  final List<double> load5;
  final List<double> load15;

  factory LoadSeries.fromJson(Map<String, dynamic> json) {
    return LoadSeries(
      load1: _dList(json['load1']),
      load5: _dList(json['load5']),
      load15: _dList(json['load15']),
    );
  }
}

/// CPU 历史序列（百分比）。
class CpuSeries {
  const CpuSeries({required this.percent});

  final List<double> percent;

  factory CpuSeries.fromJson(Map<String, dynamic> json) {
    return CpuSeries(percent: _dList(json['percent']));
  }
}

/// 内存历史序列（MB）。
class MemSeries {
  const MemSeries({
    required this.total,
    required this.available,
    required this.used,
  });

  /// 总量（MB）。
  final double total;

  final List<double> available;
  final List<double> used;

  factory MemSeries.fromJson(Map<String, dynamic> json) {
    return MemSeries(
      total: _d(json['total']),
      available: _dList(json['available']),
      used: _dList(json['used']),
    );
  }
}

/// SWAP 历史序列（MB）。
class SwapSeries {
  const SwapSeries({
    required this.total,
    required this.used,
    required this.free,
  });

  final double total;
  final List<double> used;
  final List<double> free;

  factory SwapSeries.fromJson(Map<String, dynamic> json) {
    return SwapSeries(
      total: _d(json['total']),
      used: _dList(json['used']),
      free: _dList(json['free']),
    );
  }
}

/// 单个网卡的历史序列（sent/recv 为累计 MB，tx/rx 为 MB/s）。
class NetworkSeries {
  const NetworkSeries({
    required this.name,
    required this.sent,
    required this.recv,
    required this.tx,
    required this.rx,
  });

  final String name;
  final List<double> sent;
  final List<double> recv;
  final List<double> tx;
  final List<double> rx;

  factory NetworkSeries.fromJson(Map<String, dynamic> json) {
    return NetworkSeries(
      name: json['name']?.toString() ?? '',
      sent: _dList(json['sent']),
      recv: _dList(json['recv']),
      tx: _dList(json['tx']),
      rx: _dList(json['rx']),
    );
  }
}

/// 单块磁盘的 IO 历史序列（read/write_bytes 为累计 MB，speed 为 KB/s）。
class DiskIoSeries {
  const DiskIoSeries({
    required this.name,
    required this.readBytes,
    required this.writeBytes,
    required this.readSpeed,
    required this.writeSpeed,
  });

  final String name;
  final List<double> readBytes;
  final List<double> writeBytes;
  final List<double> readSpeed;
  final List<double> writeSpeed;

  factory DiskIoSeries.fromJson(Map<String, dynamic> json) {
    return DiskIoSeries(
      name: json['name']?.toString() ?? '',
      readBytes: _dList(json['read_bytes']),
      writeBytes: _dList(json['write_bytes']),
      readSpeed: _dList(json['read_speed']),
      writeSpeed: _dList(json['write_speed']),
    );
  }
}

/// `GET /monitor/list?start=&end=` 响应（types.MonitorDetail）。
class MonitorDetail {
  const MonitorDetail({
    required this.times,
    required this.load,
    required this.cpu,
    required this.mem,
    required this.swap,
    required this.net,
    required this.diskIo,
  });

  /// 采样时间（"yyyy-MM-dd HH:mm:ss"）。
  final List<String> times;

  final LoadSeries load;
  final CpuSeries cpu;
  final MemSeries mem;
  final SwapSeries swap;
  final List<NetworkSeries> net;
  final List<DiskIoSeries> diskIo;

  bool get isEmpty => times.isEmpty;

  factory MonitorDetail.fromJson(Map<String, dynamic> json) {
    return MonitorDetail(
      times: (json['times'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      load: json['load'] is Map<String, dynamic>
          ? LoadSeries.fromJson(json['load'] as Map<String, dynamic>)
          : const LoadSeries(load1: [], load5: [], load15: []),
      cpu: json['cpu'] is Map<String, dynamic>
          ? CpuSeries.fromJson(json['cpu'] as Map<String, dynamic>)
          : const CpuSeries(percent: []),
      mem: json['mem'] is Map<String, dynamic>
          ? MemSeries.fromJson(json['mem'] as Map<String, dynamic>)
          : const MemSeries(total: 0, available: [], used: []),
      swap: json['swap'] is Map<String, dynamic>
          ? SwapSeries.fromJson(json['swap'] as Map<String, dynamic>)
          : const SwapSeries(total: 0, used: [], free: []),
      net: (json['net'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(NetworkSeries.fromJson)
              .toList() ??
          const [],
      diskIo: (json['disk_io'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(DiskIoSeries.fromJson)
              .toList() ??
          const [],
    );
  }
}
