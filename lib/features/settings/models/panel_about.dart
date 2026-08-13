/// 面板基础信息。
///
/// 对应 `GET /api/home/panel`（`internal/service/home.go` `Panel()`）：
/// `{ name, locale, hidden_menu, custom_logo }`。
class PanelBasicInfo {
  const PanelBasicInfo({
    this.name = '',
    this.locale = '',
    this.hiddenMenu = const [],
    this.customLogo = '',
  });

  final String name;
  final String locale;
  final List<String> hiddenMenu;
  final String customLogo;

  factory PanelBasicInfo.fromJson(Map<String, dynamic> json) {
    return PanelBasicInfo(
      name: json['name'] as String? ?? '',
      locale: json['locale'] as String? ?? '',
      hiddenMenu: json['hidden_menu'] is List
          ? (json['hidden_menu'] as List).map((e) => '$e').toList()
          : const [],
      customLogo: json['custom_logo'] as String? ?? '',
    );
  }
}

/// 面板 / 系统版本信息。
///
/// 对应 `GET /api/home/system_info`（`internal/service/home.go` `SystemInfo()`）。
/// 这里只取「关于」页需要的字段，其余（nets / disks 等）交由首页模块使用。
class PanelSystemInfo {
  const PanelSystemInfo({
    this.hostname = '',
    this.panelVersion = '',
    this.commitHash = '',
    this.buildId = '',
    this.buildTime = '',
    this.goVersion = '',
    this.kernelArch = '',
    this.kernelVersion = '',
    this.osName = '',
    this.osSupported = true,
    this.osEol = false,
    this.uptime = 0,
    this.bootTime = 0,
  });

  final String hostname;
  final String panelVersion;
  final String commitHash;
  final String buildId;
  final String buildTime;
  final String goVersion;
  final String kernelArch;
  final String kernelVersion;
  final String osName;

  /// 系统版本是否受面板支持。
  final bool osSupported;

  /// 系统是否已停止维护（EOL）。
  final bool osEol;

  /// 运行时长（秒）。
  final int uptime;

  /// 开机时间（unix 秒）。
  final int bootTime;

  /// 人类可读的运行时长，如 `3 天 4 小时`。
  String get uptimeLabel {
    if (uptime <= 0) return '-';
    final days = uptime ~/ 86400;
    final hours = (uptime % 86400) ~/ 3600;
    final minutes = (uptime % 3600) ~/ 60;
    if (days > 0) return '$days 天 $hours 小时';
    if (hours > 0) return '$hours 小时 $minutes 分钟';
    return '$minutes 分钟';
  }

  factory PanelSystemInfo.fromJson(Map<String, dynamic> json) {
    return PanelSystemInfo(
      hostname: _str(json['hostname']),
      panelVersion: _str(json['panel_version']),
      commitHash: _str(json['commit_hash']),
      buildId: _str(json['build_id']),
      buildTime: _str(json['build_time']),
      goVersion: _str(json['go_version']),
      kernelArch: _str(json['kernel_arch']),
      kernelVersion: _str(json['kernel_version']),
      osName: _str(json['os_name']),
      osSupported: json['os_supported'] is bool
          ? json['os_supported'] as bool
          : true,
      osEol: json['os_eol'] is bool ? json['os_eol'] as bool : false,
      uptime: _int(json['uptime']),
      bootTime: _int(json['boot_time']),
    );
  }

  static String _str(dynamic v) {
    if (v == null) return '';
    if (v is String) return v;
    return '$v';
  }

  static int _int(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
}

/// 「关于」页聚合数据：面板基础信息 + 系统信息 + 当前用户。
class AboutInfo {
  const AboutInfo({
    required this.panel,
    required this.system,
    this.userName = '',
    this.userEmail = '',
  });

  final PanelBasicInfo panel;
  final PanelSystemInfo system;

  /// 当前 API 令牌所属用户（`GET /api/user/info`），获取失败时为空串。
  final String userName;
  final String userEmail;
}
