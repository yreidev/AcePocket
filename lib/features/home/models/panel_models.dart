/// 首页相关模型：面板信息、系统信息、统计信息、首页应用、健康问题。
///
/// 字段以面板源码为准：
/// - `internal/service/home.go` 各 Handler 的 Success(...) 响应
/// - `internal/app/health.go` HealthIssue
library;

/// 通用 Label/Value 对（面板 types.LV / types.LVInt，value 容忍字符串或数字）。
class LabelValue {
  const LabelValue({required this.label, required this.value});

  final String label;
  final String value;

  factory LabelValue.fromJson(Map<String, dynamic> json) {
    return LabelValue(
      label: json['label']?.toString() ?? '',
      value: json['value']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'label': label, 'value': value};
}

/// `GET /home/panel` 响应。
class PanelInfo {
  const PanelInfo({
    required this.name,
    required this.locale,
    required this.hiddenMenu,
    required this.customLogo,
  });

  final String name;
  final String locale;
  final List<String> hiddenMenu;
  final String customLogo;

  factory PanelInfo.fromJson(Map<String, dynamic> json) {
    return PanelInfo(
      name: json['name'] as String? ?? 'AcePanel',
      locale: json['locale'] as String? ?? '',
      hiddenMenu:
          (json['hidden_menu'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      customLogo: json['custom_logo'] as String? ?? '',
    );
  }
}

/// `GET /home/system_info` 响应。
class SystemInfo {
  const SystemInfo({
    required this.procs,
    required this.hostname,
    required this.panelVersion,
    required this.commitHash,
    required this.buildId,
    required this.buildTime,
    required this.buildUser,
    required this.buildHost,
    required this.goVersion,
    required this.kernelArch,
    required this.kernelVersion,
    required this.osName,
    required this.osSupported,
    required this.osEol,
    required this.bootTime,
    required this.uptime,
    required this.nets,
    required this.disks,
  });

  final int procs;
  final String hostname;
  final String panelVersion;
  final String commitHash;
  final String buildId;
  final String buildTime;
  final String buildUser;
  final String buildHost;
  final String goVersion;
  final String kernelArch;
  final String kernelVersion;
  final String osName;
  final bool osSupported;
  final bool osEol;

  /// 开机时间（unix 秒）。
  final int bootTime;

  /// 运行时长（秒）。
  final int uptime;

  /// 网卡列表（label/value 均为网卡名）。
  final List<LabelValue> nets;

  /// 磁盘列表（value 为设备名，label 为 `设备 (挂载点)`）。
  final List<LabelValue> disks;

  factory SystemInfo.fromJson(Map<String, dynamic> json) {
    return SystemInfo(
      procs: (json['procs'] as num?)?.toInt() ?? 0,
      hostname: json['hostname'] as String? ?? '',
      panelVersion: json['panel_version'] as String? ?? '',
      commitHash: json['commit_hash'] as String? ?? '',
      buildId: json['build_id'] as String? ?? '',
      buildTime: json['build_time'] as String? ?? '',
      buildUser: json['build_user'] as String? ?? '',
      buildHost: json['build_host'] as String? ?? '',
      goVersion: json['go_version'] as String? ?? '',
      kernelArch: json['kernel_arch'] as String? ?? '',
      kernelVersion: json['kernel_version'] as String? ?? '',
      osName: json['os_name'] as String? ?? '',
      osSupported: json['os_supported'] as bool? ?? true,
      osEol: json['os_eol'] as bool? ?? false,
      bootTime: (json['boot_time'] as num?)?.toInt() ?? 0,
      uptime: (json['uptime'] as num?)?.toInt() ?? 0,
      nets:
          (json['nets'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(LabelValue.fromJson)
              .toList() ??
          const [],
      disks:
          (json['disks'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(LabelValue.fromJson)
              .toList() ??
          const [],
    );
  }
}

/// `GET /home/count_info` 响应（获取失败的项为 -1）。
class CountInfo {
  const CountInfo({
    required this.website,
    required this.database,
    required this.project,
    required this.cron,
    required this.container,
  });

  final int website;
  final int database;
  final int project;
  final int cron;
  final int container;

  factory CountInfo.fromJson(Map<String, dynamic> json) {
    return CountInfo(
      website: (json['website'] as num?)?.toInt() ?? -1,
      database: (json['database'] as num?)?.toInt() ?? -1,
      project: (json['project'] as num?)?.toInt() ?? -1,
      cron: (json['cron'] as num?)?.toInt() ?? -1,
      container: (json['container'] as num?)?.toInt() ?? -1,
    );
  }
}

/// `GET /home/apps` 响应中的一项（首页展示应用）。
class HomeApp {
  const HomeApp({
    required this.name,
    required this.description,
    required this.slug,
    required this.version,
  });

  final String name;
  final String description;
  final String slug;
  final String version;

  factory HomeApp.fromJson(Map<String, dynamic> json) {
    return HomeApp(
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      version: json['version'] as String? ?? '',
    );
  }
}

/// `GET /home/health` 响应中的一项（面板健康问题）。
class HealthIssue {
  const HealthIssue({
    required this.key,
    required this.level,
    required this.message,
    required this.since,
  });

  /// 稳定标识符，如 `database:stat`。
  final String key;

  /// `error` 或 `warning`。
  final String level;

  final String message;

  /// 首次发生时间（RFC3339），解析失败为 null。
  final DateTime? since;

  bool get isError => level == 'error';

  factory HealthIssue.fromJson(Map<String, dynamic> json) {
    return HealthIssue(
      key: json['key'] as String? ?? '',
      level: json['level'] as String? ?? 'warning',
      message: json['message'] as String? ?? '',
      since: DateTime.tryParse(json['since'] as String? ?? '')?.toLocal(),
    );
  }
}

/// `GET /home/top_processes?type=` 响应中的一项（types.ProcessStat）。
class ProcessStat {
  const ProcessStat({
    required this.pid,
    required this.name,
    required this.username,
    required this.command,
    required this.value,
    required this.read,
    required this.write,
  });

  final int pid;
  final String name;
  final String username;
  final String command;

  /// 主指标值。以 `pkg/tools/tools.go` 的 `CollectTopProcesses` 实现为准：
  /// `cpu` 为百分比，`memory` 为进程 RSS **字节数**，`disk_io` 为读写累计字节数。
  final double value;

  /// 仅磁盘 IO：读取字节。
  final double read;

  /// 仅磁盘 IO：写入字节。
  final double write;

  factory ProcessStat.fromJson(Map<String, dynamic> json) {
    return ProcessStat(
      pid: (json['pid'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
      username: json['username'] as String? ?? '',
      command: json['command'] as String? ?? '',
      value: (json['value'] as num?)?.toDouble() ?? 0,
      read: (json['read'] as num?)?.toDouble() ?? 0,
      write: (json['write'] as num?)?.toDouble() ?? 0,
    );
  }
}
