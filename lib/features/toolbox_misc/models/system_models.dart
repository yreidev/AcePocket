/// 系统工具箱（`internal/route/toolbox_system.go`）相关数据模型。
///
/// 字段名严格对齐面板 `internal/service/toolbox_system.go` 的响应结构。
library;

/// 分区加载结果：成功持有值，失败持有异常。
///
/// 系统工具箱一次要读取 6 类互不相干的信息（DNS / SWAP / 时区 / NTP / 主机名 /
/// hosts），任意一项失败不应让整页不可用，因此按分区分别记录成败。
class SectionResult<T> {
  const SectionResult.data(T value) : _value = value, error = null;

  const SectionResult.failure(Object this.error) : _value = null;

  final T? _value;
  final Object? error;

  bool get ok => error == null;

  /// 成功时的值；失败时访问会抛出，调用前请先判断 [ok]。
  T get value {
    final v = _value;
    if (v == null) {
      throw StateError('分区数据加载失败：$error');
    }
    return v;
  }

  /// 成功时的值，失败时返回 null。
  T? get valueOrNull => _value;
}

/// DNS 配置（GET /toolbox_system/dns）。
///
/// 响应：`{"dns": ["1.1.1.1", "8.8.8.8"], "manager": "NetworkManager"}`
class DnsInfo {
  const DnsInfo({required this.servers, required this.manager});

  /// 当前生效的 DNS 服务器列表。
  final List<String> servers;

  /// DNS 管理方式：`NetworkManager` / `netplan` / `resolv.conf` / `unknown`。
  final String manager;

  factory DnsInfo.fromJson(Map<String, dynamic> json) {
    final raw = json['dns'];
    return DnsInfo(
      servers: raw is List
          ? raw.map((e) => '$e').where((e) => e.isNotEmpty).toList()
          : const [],
      manager: json['manager'] as String? ?? 'unknown',
    );
  }

  String get dns1 => servers.isNotEmpty ? servers[0] : '';

  String get dns2 => servers.length > 1 ? servers[1] : '';

  /// 管理方式的中文说明。
  String get managerLabel => switch (manager) {
    'NetworkManager' => 'NetworkManager（网络管理器）',
    'netplan' => 'netplan（Ubuntu 网络配置）',
    'resolv.conf' => 'resolv.conf（直接写配置文件）',
    _ => '未识别',
  };

  /// resolv.conf 方式下的修改会在重启后被系统覆盖。
  bool get isResolvConf => manager == 'resolv.conf' || manager == 'unknown';
}

/// SWAP 信息（GET /toolbox_system/swap）。
///
/// 响应：`{"total": "2.00 GB", "size": 2048, "used": "0.00 B", "free": "2.00 GB"}`
/// 其中 `size` 是面板托管的 swap 文件大小（单位 MB），其余为系统统计值。
class SwapInfo {
  const SwapInfo({
    required this.total,
    required this.used,
    required this.free,
    required this.size,
  });

  final String total;
  final String used;
  final String free;

  /// 面板 swap 文件大小（MB），0 表示面板未创建 swap 文件。
  final int size;

  factory SwapInfo.fromJson(Map<String, dynamic> json) => SwapInfo(
    total: json['total'] as String? ?? '0.00 B',
    used: json['used'] as String? ?? '0.00 B',
    free: json['free'] as String? ?? '0.00 B',
    size: (json['size'] as num?)?.toInt() ?? 0,
  );

  bool get enabled => size > 0;
}

/// 时区信息（GET /toolbox_system/timezone）。
///
/// 响应：`{"timezone": "Asia/Shanghai", "timezones": [{"label": ..., "value": ...}]}`
class TimezoneInfo {
  const TimezoneInfo({required this.timezone, required this.timezones});

  /// 当前时区，如 `Asia/Shanghai`。
  final String timezone;

  /// 系统支持的全部时区（`timedatectl list-timezones`）。
  final List<String> timezones;

  factory TimezoneInfo.fromJson(Map<String, dynamic> json) {
    final raw = json['timezones'];
    final zones = <String>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map<String, dynamic>) {
          final value = item['value'] as String? ?? '';
          if (value.isNotEmpty) zones.add(value);
        } else if (item is String && item.isNotEmpty) {
          zones.add(item);
        }
      }
    }
    return TimezoneInfo(
      timezone: json['timezone'] as String? ?? '',
      timezones: zones,
    );
  }
}

/// 系统 NTP 配置（GET /toolbox_system/ntp_servers）。
///
/// 响应：`{"service_type": "chrony", "servers": [...], "builtins": [...]}`
class NtpConfig {
  const NtpConfig({
    required this.serviceType,
    required this.servers,
    required this.builtins,
  });

  /// `timesyncd` / `chrony` / `unknown`。
  final String serviceType;

  /// 系统当前配置的 NTP 服务器。
  final List<String> servers;

  /// 面板内置的可选 NTP 服务器（同步时间时的候选）。
  final List<String> builtins;

  factory NtpConfig.fromJson(Map<String, dynamic> json) => NtpConfig(
    serviceType: json['service_type'] as String? ?? 'unknown',
    servers: _stringList(json['servers']),
    builtins: _stringList(json['builtins']),
  );

  static List<String> _stringList(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map((e) => '$e').where((e) => e.isNotEmpty).toList();
  }

  String get serviceTypeLabel => switch (serviceType) {
    'timesyncd' => 'systemd-timesyncd',
    'chrony' => 'chrony',
    _ => '未检测到 NTP 服务',
  };

  /// 系统未安装 timesyncd / chrony 时无法写入 NTP 配置。
  bool get supported => serviceType == 'timesyncd' || serviceType == 'chrony';
}

/// 系统工具箱聚合数据（一次并行拉取全部分区）。
class SystemToolsInfo {
  const SystemToolsInfo({
    required this.dns,
    required this.swap,
    required this.timezone,
    required this.ntp,
    required this.hostname,
    required this.hosts,
  });

  final SectionResult<DnsInfo> dns;
  final SectionResult<SwapInfo> swap;
  final SectionResult<TimezoneInfo> timezone;
  final SectionResult<NtpConfig> ntp;
  final SectionResult<String> hostname;
  final SectionResult<String> hosts;
}
