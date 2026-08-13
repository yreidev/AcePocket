/// 「服务器接入与管理」模块的数据模型。
///
/// 字段与面板源码逐一对齐（internal/route/home.go + internal/service/home.go）：
/// - `GET /api/home/panel`        → `HomeService.Panel()`（`Public: true`，无需认证）
/// - `GET /api/home/system_info`  → `HomeService.SystemInfo()`（需令牌认证）
library;

/// 面板基础信息（`GET /api/home/panel`）。
///
/// 服务端返回（home.go `Panel()`）：
/// `{name, locale, hidden_menu, custom_logo}`。
class PanelInfo {
  const PanelInfo({
    required this.name,
    required this.locale,
    required this.hiddenMenu,
    required this.customLogo,
  });

  /// 面板名称（未自定义时为「AcePanel」）。
  final String name;

  /// 面板语言环境，如 `zh_CN`。
  final String locale;

  /// 被隐藏的菜单项列表。
  final List<String> hiddenMenu;

  /// 自定义 Logo 地址（未设置时为空字符串）。
  final String customLogo;

  factory PanelInfo.fromJson(Map<String, dynamic> json) {
    return PanelInfo(
      name: json['name'] as String? ?? '',
      locale: json['locale'] as String? ?? '',
      hiddenMenu:
          (json['hidden_menu'] as List?)
              ?.map((e) => e?.toString() ?? '')
              .where((e) => e.isNotEmpty)
              .toList() ??
          const <String>[],
      customLogo: json['custom_logo'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'locale': locale,
    'hidden_menu': hiddenMenu,
    'custom_logo': customLogo,
  };
}

/// 系统信息（`GET /api/home/system_info`）。
///
/// 服务端返回（home.go `SystemInfo()`）：
/// `{procs, hostname, panel_version, commit_hash, build_id, build_time,
///   build_user, build_host, go_version, kernel_arch, kernel_version,
///   os_name, os_supported, os_eol, boot_time, uptime, nets, disks}`。
///
/// 本模块只做「连接测试 / 服务器概览」，因此不收录 `nets` / `disks`
/// （由监控模块按需解析），其余标量字段全部保留。
class SystemInfoBrief {
  const SystemInfoBrief({
    required this.hostname,
    required this.panelVersion,
    required this.commitHash,
    required this.buildId,
    required this.buildTime,
    required this.goVersion,
    required this.osName,
    required this.kernelArch,
    required this.kernelVersion,
    required this.uptimeSeconds,
    required this.bootTime,
    required this.procs,
    required this.osSupported,
    required this.osEol,
  });

  /// 主机名。
  final String hostname;

  /// 面板版本，如 `v3.3.0`。
  final String panelVersion;

  /// 面板构建的 git commit。
  final String commitHash;

  /// 面板构建 ID。
  final String buildId;

  /// 面板构建时间。
  final String buildTime;

  /// 面板编译使用的 Go 版本。
  final String goVersion;

  /// 操作系统名称与版本，如 `debian 12.5`。
  final String osName;

  /// 内核架构，如 `x86_64`。
  final String kernelArch;

  /// 内核版本。
  final String kernelVersion;

  /// 系统已运行秒数。
  final int uptimeSeconds;

  /// 开机时间（Unix 秒）。
  final int bootTime;

  /// 进程数。
  final int procs;

  /// 面板是否官方支持当前系统版本。
  final bool osSupported;

  /// 当前系统是否已停止维护（EOL）。
  final bool osEol;

  factory SystemInfoBrief.fromJson(Map<String, dynamic> json) {
    return SystemInfoBrief(
      hostname: json['hostname'] as String? ?? '',
      panelVersion: json['panel_version'] as String? ?? '',
      commitHash: json['commit_hash'] as String? ?? '',
      buildId: json['build_id'] as String? ?? '',
      buildTime: json['build_time'] as String? ?? '',
      goVersion: json['go_version'] as String? ?? '',
      osName: json['os_name'] as String? ?? '',
      kernelArch: json['kernel_arch'] as String? ?? '',
      kernelVersion: json['kernel_version'] as String? ?? '',
      uptimeSeconds: (json['uptime'] as num?)?.toInt() ?? 0,
      bootTime: (json['boot_time'] as num?)?.toInt() ?? 0,
      procs: (json['procs'] as num?)?.toInt() ?? 0,
      osSupported: json['os_supported'] as bool? ?? true,
      osEol: json['os_eol'] as bool? ?? false,
    );
  }

  /// 「x 天 x 小时」形式的已运行时长。
  String get uptimeText {
    if (uptimeSeconds <= 0) return '-';
    final days = uptimeSeconds ~/ 86400;
    final hours = (uptimeSeconds % 86400) ~/ 3600;
    final minutes = (uptimeSeconds % 3600) ~/ 60;
    if (days > 0) return '$days 天 $hours 小时';
    if (hours > 0) return '$hours 小时 $minutes 分钟';
    return '$minutes 分钟';
  }

  Map<String, dynamic> toJson() => {
    'hostname': hostname,
    'panel_version': panelVersion,
    'commit_hash': commitHash,
    'build_id': buildId,
    'build_time': buildTime,
    'go_version': goVersion,
    'os_name': osName,
    'kernel_arch': kernelArch,
    'kernel_version': kernelVersion,
    'uptime': uptimeSeconds,
    'boot_time': bootTime,
    'procs': procs,
    'os_supported': osSupported,
    'os_eol': osEol,
  };
}

/// 连接测试成功的结果：面板信息 + 系统信息。
class ConnectionTestResult {
  const ConnectionTestResult({required this.panel, required this.system});

  /// `GET /api/home/panel` 的结果（验证「地址可达且确实是 AcePanel」）。
  final PanelInfo panel;

  /// `GET /api/home/system_info` 的结果（验证「令牌有效」）。
  final SystemInfoBrief system;
}
