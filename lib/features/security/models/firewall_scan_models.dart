/// 防火墙「扫描感知」相关模型。
///
/// 字段与面板源码对齐：
/// - `internal/biz/scan_event.go`（ScanSetting / ScanSummary / ScanDayTrend /
///   ScanSourceRank / ScanPortRank / ScanEvent）；
/// - `pkg/firewall/scan/types.go`（InterfaceInfo）。
library;

/// 扫描感知设置（GET/POST /firewall/scan/setting）。
class ScanSetting {
  const ScanSetting({
    required this.enabled,
    required this.days,
    required this.interfaces,
    required this.autoBlock,
    required this.blockThreshold,
    required this.blockWindow,
    required this.blockDuration,
    required this.whitelist,
  });

  /// 是否开启扫描感知。
  final bool enabled;

  /// 数据保留天数（1-365）。
  final int days;

  /// 监听的网卡名；为空表示自动检测。
  final List<String> interfaces;

  /// 是否自动封锁扫描源 IP。
  final bool autoBlock;

  /// 封锁阈值：窗口内扫描次数（1-100000）。
  final int blockThreshold;

  /// 检测窗口，单位分钟（1-1440）。
  final int blockWindow;

  /// 封锁时长，单位小时；0 表示永久。
  final int blockDuration;

  /// IP / CIDR 白名单。
  final List<String> whitelist;

  factory ScanSetting.fromJson(Map<String, dynamic> json) => ScanSetting(
    enabled: json['enabled'] as bool? ?? false,
    days: (json['days'] as num?)?.toInt() ?? 30,
    interfaces: _stringList(json['interfaces']),
    autoBlock: json['auto_block'] as bool? ?? false,
    blockThreshold: (json['block_threshold'] as num?)?.toInt() ?? 100,
    blockWindow: (json['block_window'] as num?)?.toInt() ?? 5,
    blockDuration: (json['block_duration'] as num?)?.toInt() ?? 0,
    whitelist: _stringList(json['whitelist']),
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'days': days,
    'interfaces': interfaces,
    'auto_block': autoBlock,
    'block_threshold': blockThreshold,
    'block_window': blockWindow,
    'block_duration': blockDuration,
    'whitelist': whitelist,
  };

  ScanSetting copyWith({
    bool? enabled,
    int? days,
    List<String>? interfaces,
    bool? autoBlock,
    int? blockThreshold,
    int? blockWindow,
    int? blockDuration,
    List<String>? whitelist,
  }) => ScanSetting(
    enabled: enabled ?? this.enabled,
    days: days ?? this.days,
    interfaces: interfaces ?? this.interfaces,
    autoBlock: autoBlock ?? this.autoBlock,
    blockThreshold: blockThreshold ?? this.blockThreshold,
    blockWindow: blockWindow ?? this.blockWindow,
    blockDuration: blockDuration ?? this.blockDuration,
    whitelist: whitelist ?? this.whitelist,
  );

  static List<String> _stringList(dynamic value) =>
      value is List ? value.whereType<String>().toList() : const [];
}

/// 可用网卡（GET /firewall/scan/interfaces）。
class NetInterface {
  const NetInterface({
    required this.name,
    required this.ips,
    required this.status,
  });

  final String name;
  final List<String> ips;

  /// `up` / `down`。
  final String status;

  factory NetInterface.fromJson(Map<String, dynamic> json) => NetInterface(
    name: json['name'] as String? ?? '',
    ips: ScanSetting._stringList(json['ips']),
    status: json['status'] as String? ?? '',
  );

  String get label => ips.isEmpty ? name : '$name（${ips.join(', ')}）';
}

/// 扫描汇总（GET /firewall/scan/summary）。
class ScanSummary {
  const ScanSummary({
    required this.totalCount,
    required this.uniqueIps,
    required this.uniquePorts,
  });

  final int totalCount;
  final int uniqueIps;
  final int uniquePorts;

  factory ScanSummary.fromJson(Map<String, dynamic> json) => ScanSummary(
    totalCount: (json['total_count'] as num?)?.toInt() ?? 0,
    uniqueIps: (json['unique_ips'] as num?)?.toInt() ?? 0,
    uniquePorts: (json['unique_ports'] as num?)?.toInt() ?? 0,
  );

  static const empty = ScanSummary(totalCount: 0, uniqueIps: 0, uniquePorts: 0);
}

/// 每日扫描趋势（GET /firewall/scan/trend）。
class ScanDayTrend {
  const ScanDayTrend({
    required this.date,
    required this.totalCount,
    required this.uniqueIps,
  });

  /// `YYYY-MM-DD`。
  final String date;
  final int totalCount;
  final int uniqueIps;

  factory ScanDayTrend.fromJson(Map<String, dynamic> json) => ScanDayTrend(
    date: json['date'] as String? ?? '',
    totalCount: (json['total_count'] as num?)?.toInt() ?? 0,
    uniqueIps: (json['unique_ips'] as num?)?.toInt() ?? 0,
  );
}

/// 扫描源 IP 排行（GET /firewall/scan/top_ips）。
class ScanSourceRank {
  const ScanSourceRank({
    required this.sourceIp,
    required this.totalCount,
    required this.portCount,
    required this.lastSeen,
    required this.country,
    required this.region,
    required this.city,
    required this.isp,
  });

  final String sourceIp;
  final int totalCount;
  final int portCount;
  final String lastSeen;
  final String country;
  final String region;
  final String city;
  final String isp;

  factory ScanSourceRank.fromJson(Map<String, dynamic> json) => ScanSourceRank(
    sourceIp: json['source_ip'] as String? ?? '',
    totalCount: (json['total_count'] as num?)?.toInt() ?? 0,
    portCount: (json['port_count'] as num?)?.toInt() ?? 0,
    lastSeen: json['last_seen'] as String? ?? '',
    country: json['country'] as String? ?? '',
    region: json['region'] as String? ?? '',
    city: json['city'] as String? ?? '',
    isp: json['isp'] as String? ?? '',
  );

  /// 归属地展示（国家 / 地区 / 城市 / 运营商，去空去重）。
  String get location {
    final parts = <String>[];
    for (final part in [country, region, city, isp]) {
      final value = part.trim();
      if (value.isNotEmpty && !parts.contains(value)) parts.add(value);
    }
    return parts.join(' · ');
  }
}

/// 被扫描端口排行（GET /firewall/scan/top_ports）。
class ScanPortRank {
  const ScanPortRank({
    required this.port,
    required this.protocol,
    required this.totalCount,
    required this.ipCount,
  });

  final int port;
  final String protocol;
  final int totalCount;
  final int ipCount;

  factory ScanPortRank.fromJson(Map<String, dynamic> json) => ScanPortRank(
    port: (json['port'] as num?)?.toInt() ?? 0,
    protocol: json['protocol'] as String? ?? 'tcp',
    totalCount: (json['total_count'] as num?)?.toInt() ?? 0,
    ipCount: (json['ip_count'] as num?)?.toInt() ?? 0,
  );
}

/// 扫描感知概览（汇总 + 趋势 + Top 排行的组合，供概览页一次性展示）。
class ScanOverview {
  const ScanOverview({
    required this.summary,
    required this.trend,
    required this.topIps,
    required this.topPorts,
  });

  final ScanSummary summary;
  final List<ScanDayTrend> trend;
  final List<ScanSourceRank> topIps;
  final List<ScanPortRank> topPorts;
}

/// 扫描事件（GET /firewall/scan/events 的 items 元素）。
class ScanEvent {
  const ScanEvent({
    required this.id,
    required this.sourceIp,
    required this.port,
    required this.protocol,
    required this.date,
    required this.count,
    required this.country,
    required this.region,
    required this.city,
    required this.isp,
    this.firstSeen,
    this.lastSeen,
  });

  final int id;
  final String sourceIp;
  final int port;
  final String protocol;

  /// `YYYY-MM-DD`。
  final String date;
  final int count;
  final String country;
  final String region;
  final String city;
  final String isp;
  final DateTime? firstSeen;
  final DateTime? lastSeen;

  factory ScanEvent.fromJson(Map<String, dynamic> json) => ScanEvent(
    id: (json['id'] as num?)?.toInt() ?? 0,
    sourceIp: json['source_ip'] as String? ?? '',
    port: (json['port'] as num?)?.toInt() ?? 0,
    protocol: json['protocol'] as String? ?? 'tcp',
    date: json['date'] as String? ?? '',
    count: (json['count'] as num?)?.toInt() ?? 0,
    country: json['country'] as String? ?? '',
    region: json['region'] as String? ?? '',
    city: json['city'] as String? ?? '',
    isp: json['isp'] as String? ?? '',
    firstSeen: _parseTime(json['first_seen']),
    lastSeen: _parseTime(json['last_seen']),
  );

  String get location {
    final parts = <String>[];
    for (final part in [country, region, city, isp]) {
      final value = part.trim();
      if (value.isNotEmpty && !parts.contains(value)) parts.add(value);
    }
    return parts.join(' · ');
  }

  static DateTime? _parseTime(dynamic value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;
}
