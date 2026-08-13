/// 防篡改相关模型。
///
/// 字段与面板源码对齐：
/// - `internal/biz/tamper.go`（TamperSetting / TamperRule / TamperLog）；
/// - `pkg/tamper/types.go`（Stats / EBPFStatus）；
/// - `internal/service/tamper.go` `Status()` 的组合响应。
library;

/// 防篡改全局设置（GET/POST /tamper/setting）。
class TamperSetting {
  const TamperSetting({
    required this.enabled,
    required this.mode,
    required this.blockNewFiles,
    required this.logDays,
  });

  final bool enabled;

  /// 保护模式：`chattr` / `ebpf`。
  final String mode;

  /// 拦截新建受保护类型文件。
  final bool blockNewFiles;

  /// 日志保留天数。
  final int logDays;

  factory TamperSetting.fromJson(Map<String, dynamic> json) => TamperSetting(
    enabled: json['enabled'] as bool? ?? false,
    mode: json['mode'] as String? ?? 'chattr',
    blockNewFiles: json['block_new_files'] as bool? ?? false,
    logDays: (json['log_days'] as num?)?.toInt() ?? 30,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'mode': mode,
    'block_new_files': blockNewFiles,
    'log_days': logDays,
  };

  TamperSetting copyWith({
    bool? enabled,
    String? mode,
    bool? blockNewFiles,
    int? logDays,
  }) => TamperSetting(
    enabled: enabled ?? this.enabled,
    mode: mode ?? this.mode,
    blockNewFiles: blockNewFiles ?? this.blockNewFiles,
    logDays: logDays ?? this.logDays,
  );
}

/// 防篡改运行统计（tamper status 响应的 `stats` 字段）。
class TamperStats {
  const TamperStats({
    required this.mode,
    required this.running,
    required this.protectedFiles,
    required this.protectedDirs,
  });

  final String mode;
  final bool running;
  final int protectedFiles;
  final int protectedDirs;

  factory TamperStats.fromJson(Map<String, dynamic> json) => TamperStats(
    mode: json['mode'] as String? ?? '',
    running: json['running'] as bool? ?? false,
    protectedFiles: (json['protected_files'] as num?)?.toInt() ?? 0,
    protectedDirs: (json['protected_dirs'] as num?)?.toInt() ?? 0,
  );
}

/// eBPF 模式可用性检测（tamper status 响应的 `ebpf` 字段）。
class EbpfStatus {
  const EbpfStatus({
    required this.available,
    required this.kernelVersion,
    required this.bpfLsmActive,
    required this.activeLsm,
    required this.reason,
  });

  final bool available;
  final String kernelVersion;
  final bool bpfLsmActive;
  final String activeLsm;
  final String reason;

  factory EbpfStatus.fromJson(Map<String, dynamic> json) => EbpfStatus(
    available: json['available'] as bool? ?? false,
    kernelVersion: json['kernel_version'] as String? ?? '',
    bpfLsmActive: json['bpf_lsm_active'] as bool? ?? false,
    activeLsm: json['active_lsm'] as String? ?? '',
    reason: json['reason'] as String? ?? '',
  );
}

/// 防篡改整体状态（GET /tamper/status）。
class TamperStatus {
  const TamperStatus({
    required this.supported,
    required this.setting,
    required this.stats,
    required this.ebpf,
  });

  final bool supported;
  final TamperSetting setting;
  final TamperStats stats;
  final EbpfStatus ebpf;

  factory TamperStatus.fromJson(Map<String, dynamic> json) => TamperStatus(
    supported: json['supported'] as bool? ?? false,
    setting: TamperSetting.fromJson(
      json['setting'] as Map<String, dynamic>? ?? const {},
    ),
    stats: TamperStats.fromJson(
      json['stats'] as Map<String, dynamic>? ?? const {},
    ),
    ebpf: EbpfStatus.fromJson(
      json['ebpf'] as Map<String, dynamic>? ?? const {},
    ),
  );
}

/// 路径保护状态查询结果（POST /tamper/check_paths）。
///
/// 响应结构见 `internal/service/tamper.go` `CheckPaths()`：
/// `{"running": bool, "items": {"<path>": bool}}`。
class TamperPathCheck {
  const TamperPathCheck({required this.running, required this.items});

  /// 防篡改是否正在运行（未运行时 [items] 全为 false）。
  final bool running;

  /// 路径 -> 是否处于保护范围。
  final Map<String, bool> items;

  static const TamperPathCheck empty = TamperPathCheck(
    running: false,
    items: {},
  );

  factory TamperPathCheck.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    final items = <String, bool>{};
    if (raw is Map) {
      raw.forEach((key, value) => items['$key'] = value == true);
    }
    return TamperPathCheck(
      running: json['running'] as bool? ?? false,
      items: items,
    );
  }

  /// 指定路径是否受保护（未查询到时按未保护处理）。
  bool protectedOf(String path) => items[path] ?? false;
}

/// 防篡改保护规则（GET /tamper/rule 的 items 元素）。
class TamperRule {
  const TamperRule({
    required this.id,
    required this.name,
    required this.path,
    required this.exts,
    required this.excludes,
    required this.enabled,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String name;
  final String path;

  /// 受保护后缀，空 = 全部。
  final List<String> exts;

  /// 排除子路径。
  final List<String> excludes;
  final bool enabled;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory TamperRule.fromJson(Map<String, dynamic> json) => TamperRule(
    id: (json['id'] as num?)?.toInt() ?? 0,
    name: json['name'] as String? ?? '',
    path: json['path'] as String? ?? '',
    exts: _stringList(json['exts']),
    excludes: _stringList(json['excludes']),
    enabled: json['enabled'] as bool? ?? false,
    createdAt: _parseTime(json['created_at']),
    updatedAt: _parseTime(json['updated_at']),
  );

  static List<String> _stringList(dynamic value) {
    if (value is List) {
      return value.whereType<String>().toList();
    }
    return const [];
  }

  /// 解析面板返回的 RFC3339 时间（带时区偏移）。
  ///
  /// `DateTime.parse` 对带偏移的串返回 isUtc=true 的实例，必须 `.toLocal()`
  /// 后才是本地时间；统一在解析处转换，下游格式化无需再处理。
  static DateTime? _parseTime(dynamic value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;
}

/// 防篡改规则表单值（新建 / 编辑对话框的返回结果）。
///
/// 面板的更新接口不支持修改 `name`（见 `service.TamperService.UpdateRule`），
/// 因此编辑时 [name] 仅用于展示。
class TamperRuleDraft {
  const TamperRuleDraft({
    required this.name,
    required this.path,
    required this.exts,
    required this.excludes,
    required this.enabled,
  });

  final String name;
  final String path;
  final List<String> exts;
  final List<String> excludes;
  final bool enabled;
}

/// 防篡改拦截日志（GET /tamper/log 的 items 元素）。
class TamperLog {
  const TamperLog({
    required this.id,
    required this.path,
    required this.op,
    required this.pid,
    required this.comm,
    this.createdAt,
  });

  final int id;
  final String path;

  /// 操作类型：write / unlink / rename / setattr / create。
  final String op;
  final int pid;

  /// 触发进程名。
  final String comm;
  final DateTime? createdAt;

  factory TamperLog.fromJson(Map<String, dynamic> json) => TamperLog(
    id: (json['id'] as num?)?.toInt() ?? 0,
    path: json['path'] as String? ?? '',
    op: json['op'] as String? ?? '',
    pid: (json['pid'] as num?)?.toInt() ?? 0,
    comm: json['comm'] as String? ?? '',
    createdAt: TamperRule._parseTime(json['created_at']),
  );

  /// 操作类型的中文展示。
  String get opLabel => switch (op) {
    'write' => '写入',
    'unlink' => '删除',
    'rename' => '重命名',
    'setattr' => '改属性',
    'create' => '新建',
    _ => op,
  };
}
