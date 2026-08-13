/// `POST /home/current` 实时负载响应模型。
///
/// 对应面板 `pkg/types/system.go` 的 `types.CurrentInfo`，
/// 内部结构为 gopsutil v4 各 Stat 的 JSON 序列化（camelCase 字段）。
library;

double _d(dynamic v) => v is num ? v.toDouble() : 0;
int _i(dynamic v) => v is num ? v.toInt() : 0;
String _s(dynamic v) => v?.toString() ?? '';

/// gopsutil `cpu.InfoStat`（仅保留 App 需要的字段）。
class CpuInfo {
  const CpuInfo({
    required this.cores,
    required this.modelName,
    required this.mhz,
  });

  final int cores;
  final String modelName;
  final double mhz;

  factory CpuInfo.fromJson(Map<String, dynamic> json) {
    return CpuInfo(
      cores: _i(json['cores']),
      modelName: _s(json['modelName']),
      mhz: _d(json['mhz']),
    );
  }
}

/// gopsutil `load.AvgStat`。
class LoadAvg {
  const LoadAvg({
    required this.load1,
    required this.load5,
    required this.load15,
  });

  final double load1;
  final double load5;
  final double load15;

  factory LoadAvg.fromJson(Map<String, dynamic> json) {
    return LoadAvg(
      load1: _d(json['load1']),
      load5: _d(json['load5']),
      load15: _d(json['load15']),
    );
  }
}

/// gopsutil `mem.VirtualMemoryStat`（字节）。
class MemStat {
  const MemStat({
    required this.total,
    required this.available,
    required this.used,
    required this.usedPercent,
    required this.free,
  });

  final int total;
  final int available;
  final int used;
  final double usedPercent;
  final int free;

  factory MemStat.fromJson(Map<String, dynamic> json) {
    return MemStat(
      total: _i(json['total']),
      available: _i(json['available']),
      used: _i(json['used']),
      usedPercent: _d(json['usedPercent']),
      free: _i(json['free']),
    );
  }
}

/// gopsutil `mem.SwapMemoryStat`（字节）。
class SwapStat {
  const SwapStat({
    required this.total,
    required this.used,
    required this.free,
    required this.usedPercent,
  });

  final int total;
  final int used;
  final int free;
  final double usedPercent;

  factory SwapStat.fromJson(Map<String, dynamic> json) {
    return SwapStat(
      total: _i(json['total']),
      used: _i(json['used']),
      free: _i(json['free']),
      usedPercent: _d(json['usedPercent']),
    );
  }
}

/// gopsutil `net.IOCountersStat`（累计字节）。
class NetIoStat {
  const NetIoStat({
    required this.name,
    required this.bytesSent,
    required this.bytesRecv,
    required this.packetsSent,
    required this.packetsRecv,
  });

  final String name;
  final int bytesSent;
  final int bytesRecv;
  final int packetsSent;
  final int packetsRecv;

  factory NetIoStat.fromJson(Map<String, dynamic> json) {
    return NetIoStat(
      name: _s(json['name']),
      bytesSent: _i(json['bytesSent']),
      bytesRecv: _i(json['bytesRecv']),
      packetsSent: _i(json['packetsSent']),
      packetsRecv: _i(json['packetsRecv']),
    );
  }
}

/// gopsutil `disk.IOCountersStat`（累计值）。
class DiskIoStat {
  const DiskIoStat({
    required this.name,
    required this.readBytes,
    required this.writeBytes,
    required this.readCount,
    required this.writeCount,
    required this.readTime,
    required this.writeTime,
  });

  final String name;
  final int readBytes;
  final int writeBytes;
  final int readCount;
  final int writeCount;
  final int readTime;
  final int writeTime;

  factory DiskIoStat.fromJson(Map<String, dynamic> json) {
    return DiskIoStat(
      name: _s(json['name']),
      readBytes: _i(json['readBytes']),
      writeBytes: _i(json['writeBytes']),
      readCount: _i(json['readCount']),
      writeCount: _i(json['writeCount']),
      readTime: _i(json['readTime']),
      writeTime: _i(json['writeTime']),
    );
  }
}

/// gopsutil `disk.PartitionStat`。
class DiskPartition {
  const DiskPartition({
    required this.device,
    required this.mountpoint,
    required this.fstype,
  });

  final String device;
  final String mountpoint;
  final String fstype;

  factory DiskPartition.fromJson(Map<String, dynamic> json) {
    return DiskPartition(
      device: _s(json['device']),
      mountpoint: _s(json['mountpoint']),
      fstype: _s(json['fstype']),
    );
  }
}

/// gopsutil `disk.UsageStat`（字节）。
class DiskUsage {
  const DiskUsage({
    required this.path,
    required this.fstype,
    required this.total,
    required this.free,
    required this.used,
    required this.usedPercent,
    required this.inodesUsedPercent,
  });

  final String path;
  final String fstype;
  final int total;
  final int free;
  final int used;
  final double usedPercent;
  final double inodesUsedPercent;

  factory DiskUsage.fromJson(Map<String, dynamic> json) {
    return DiskUsage(
      path: _s(json['path']),
      fstype: _s(json['fstype']),
      total: _i(json['total']),
      free: _i(json['free']),
      used: _i(json['used']),
      usedPercent: _d(json['usedPercent']),
      inodesUsedPercent: _d(json['inodesUsedPercent']),
    );
  }
}

/// `POST /home/current` 完整响应。
class CurrentInfo {
  const CurrentInfo({
    required this.cpus,
    required this.percent,
    required this.percents,
    required this.load,
    required this.mem,
    required this.swap,
    required this.net,
    required this.diskIo,
    required this.disk,
    required this.diskUsage,
    required this.time,
  });

  final List<CpuInfo> cpus;

  /// CPU 总使用率（0-100）。
  final double percent;

  /// 每个核心使用率（0-100）。
  final List<double> percents;

  final LoadAvg load;
  final MemStat mem;
  final SwapStat swap;
  final List<NetIoStat> net;
  final List<DiskIoStat> diskIo;
  final List<DiskPartition> disk;
  final List<DiskUsage> diskUsage;

  /// 服务器采样时间。
  final DateTime? time;

  /// CPU 核心总数（cpus.cores 求和；拿不到时退化为 percents 长度）。
  int get cores {
    var sum = 0;
    for (final c in cpus) {
      sum += c.cores;
    }
    if (sum <= 0) sum = percents.length;
    return sum;
  }

  /// 所有非 lo 网卡的累计发送字节。
  int get totalBytesSent {
    var sum = 0;
    for (final n in net) {
      if (n.name == 'lo') continue;
      sum += n.bytesSent;
    }
    return sum;
  }

  /// 所有非 lo 网卡的累计接收字节。
  int get totalBytesRecv {
    var sum = 0;
    for (final n in net) {
      if (n.name == 'lo') continue;
      sum += n.bytesRecv;
    }
    return sum;
  }

  /// 所有磁盘累计读取字节。
  int get totalReadBytes {
    var sum = 0;
    for (final d in diskIo) {
      sum += d.readBytes;
    }
    return sum;
  }

  /// 所有磁盘累计写入字节。
  int get totalWriteBytes {
    var sum = 0;
    for (final d in diskIo) {
      sum += d.writeBytes;
    }
    return sum;
  }

  factory CurrentInfo.fromJson(Map<String, dynamic> json) {
    return CurrentInfo(
      cpus:
          (json['cpus'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(CpuInfo.fromJson)
              .toList() ??
          const [],
      percent: _d(json['percent']),
      percents: (json['percents'] as List?)?.map(_d).toList() ?? const [],
      load: json['load'] is Map<String, dynamic>
          ? LoadAvg.fromJson(json['load'] as Map<String, dynamic>)
          : const LoadAvg(load1: 0, load5: 0, load15: 0),
      mem: json['mem'] is Map<String, dynamic>
          ? MemStat.fromJson(json['mem'] as Map<String, dynamic>)
          : const MemStat(
              total: 0,
              available: 0,
              used: 0,
              usedPercent: 0,
              free: 0,
            ),
      swap: json['swap'] is Map<String, dynamic>
          ? SwapStat.fromJson(json['swap'] as Map<String, dynamic>)
          : const SwapStat(total: 0, used: 0, free: 0, usedPercent: 0),
      net:
          (json['net'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(NetIoStat.fromJson)
              .toList() ??
          const [],
      diskIo:
          (json['disk_io'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(DiskIoStat.fromJson)
              .toList() ??
          const [],
      disk:
          (json['disk'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(DiskPartition.fromJson)
              .toList() ??
          const [],
      diskUsage:
          (json['disk_usage'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(DiskUsage.fromJson)
              .toList() ??
          const [],
      // 面板返回 RFC3339 带时区偏移（如 2026-07-26T18:13:00+08:00），
      // DateTime.parse 得到的是 isUtc=true 的实例，必须转本地时区再展示。
      time: DateTime.tryParse(json['time'] as String? ?? '')?.toLocal(),
    );
  }
}
