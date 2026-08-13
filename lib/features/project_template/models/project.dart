import 'json_utils.dart';
import 'kv_pair.dart';

/// 项目类型选项，与源码 `pkg/types/project.go` 的 `ProjectType` 常量
/// 及 `request.ProjectCreate` 的 `in:general,php,java,go,python,nodejs,dotnet` 一致。
const List<(String, String)> kProjectTypeOptions = <(String, String)>[
  ('general', '通用'),
  ('php', 'PHP'),
  ('java', 'Java'),
  ('go', 'Go'),
  ('python', 'Python'),
  ('nodejs', 'Node.js'),
  ('dotnet', '.NET'),
];

/// systemd 重启策略选项（`Service.Restart=`）。
const List<(String, String)> kProjectRestartOptions = <(String, String)>[
  ('no', '不重启'),
  ('always', '总是重启'),
  ('on-failure', '失败时重启'),
  ('on-abnormal', '异常时重启'),
  ('on-abort', '中止时重启'),
  ('on-success', '正常退出时重启'),
];

/// systemd 标准输出 / 标准错误选项（`Service.StandardOutput=` / `StandardError=`）。
const List<(String, String)> kProjectOutputOptions = <(String, String)>[
  ('journal', 'journal（journald 日志）'),
  ('syslog', 'syslog'),
  ('kmsg', 'kmsg'),
  ('null', 'null（丢弃）'),
  ('append:/var/log/', '文件（追加）'),
  ('truncate:/var/log/', '文件（覆盖）'),
];

/// systemd `ProtectSystem=` 选项。
const List<(String, String)> kProtectSystemOptions = <(String, String)>[
  ('', '关闭'),
  ('true', 'true（/usr 只读）'),
  ('full', 'full（/usr、/etc 只读）'),
  ('strict', 'strict（整个文件系统只读）'),
];

/// 项目类型显示名，未知类型原样返回。
String projectTypeLabel(String type) {
  for (final item in kProjectTypeOptions) {
    if (item.$1 == type) return item.$2;
  }
  return type.isEmpty ? '未知' : type;
}

/// 重启策略显示名。
String projectRestartLabel(String restart) {
  for (final item in kProjectRestartOptions) {
    if (item.$1 == restart) return item.$2;
  }
  return restart.isEmpty ? '默认（失败时重启）' : restart;
}

/// 项目运行状态（systemd ActiveState）。
enum ProjectStatus {
  active,
  activating,
  deactivating,
  inactive,
  failed,
  unknown,
}

ProjectStatus projectStatusOf(String status) {
  switch (status) {
    case 'active':
      return ProjectStatus.active;
    case 'activating':
      return ProjectStatus.activating;
    case 'deactivating':
      return ProjectStatus.deactivating;
    case 'inactive':
      return ProjectStatus.inactive;
    case 'failed':
      return ProjectStatus.failed;
    default:
      return ProjectStatus.unknown;
  }
}

String projectStatusLabel(String status) {
  switch (projectStatusOf(status)) {
    case ProjectStatus.active:
      return '运行中';
    case ProjectStatus.activating:
      return '启动中';
    case ProjectStatus.deactivating:
      return '停止中';
    case ProjectStatus.inactive:
      return '已停止';
    case ProjectStatus.failed:
      return '启动失败';
    case ProjectStatus.unknown:
      return status.isEmpty ? '未部署' : status;
  }
}

/// 项目详情，对应源码 `pkg/types/project.go` 的 `types.ProjectDetail`。
///
/// 列表接口 `GET /api/project` 与详情接口 `GET /api/project/{id}` 返回同一结构，
/// 其中运行状态部分由面板实时读取 systemd 得到（unit 文件不存在时为空值）。
class ProjectDetail {
  const ProjectDetail({
    required this.id,
    required this.name,
    required this.type,
    required this.description,
    required this.rootDir,
    required this.workingDir,
    required this.execStartPre,
    required this.execStartPost,
    required this.execStart,
    required this.execStop,
    required this.execReload,
    required this.user,
    required this.restart,
    required this.restartSec,
    required this.restartMax,
    required this.timeoutStartSec,
    required this.timeoutStopSec,
    required this.environments,
    required this.standardOutput,
    required this.standardError,
    required this.requires,
    required this.wants,
    required this.after,
    required this.before,
    required this.status,
    required this.enabled,
    required this.pid,
    required this.memory,
    required this.cpu,
    required this.uptime,
    required this.memoryLimit,
    required this.cpuQuota,
    required this.noNewPrivileges,
    required this.protectTmp,
    required this.protectHome,
    required this.protectSystem,
    required this.readWritePaths,
    required this.readOnlyPaths,
  });

  final int id;
  final String name;
  final String type;
  final String description;

  /// 项目路径（unit 文件不存在时也有值，来自数据库记录）。
  final String rootDir;
  final String workingDir;
  final String execStartPre;
  final String execStartPost;
  final String execStart;
  final String execStop;
  final String execReload;
  final String user;
  final String restart;
  final String restartSec;
  final int restartMax;
  final int timeoutStartSec;
  final int timeoutStopSec;
  final List<KvPair> environments;
  final String standardOutput;
  final String standardError;
  final List<String> requires;
  final List<String> wants;
  final List<String> after;
  final List<String> before;

  /// systemd ActiveState（active / inactive / failed…）。
  final String status;

  /// 是否已设置开机自启。
  final bool enabled;
  final int pid;

  /// 内存占用（字节）。
  final int memory;

  /// CPU 占用率（百分比）。
  final double cpu;

  /// 运行时长（面板返回的可读文本）。
  final String uptime;

  /// 内存限制（字节，0 表示不限制）。
  final double memoryLimit;

  /// CPU 限制（百分比，100 = 1 核；0 表示不限制）。
  final double cpuQuota;

  final bool noNewPrivileges;
  final bool protectTmp;
  final bool protectHome;
  final String protectSystem;
  final List<String> readWritePaths;
  final List<String> readOnlyPaths;

  bool get isRunning => status == 'active';

  /// unit 文件缺失时，面板只能返回数据库里的基础字段。
  bool get hasUnitFile => status.isNotEmpty || execStart.isNotEmpty;

  factory ProjectDetail.fromJson(Map<String, dynamic> json) => ProjectDetail(
    id: jsonInt(json['id']),
    name: jsonString(json['name']),
    type: jsonString(json['type']),
    description: jsonString(json['description']),
    rootDir: jsonString(json['root_dir']),
    workingDir: jsonString(json['working_dir']),
    execStartPre: jsonString(json['exec_start_pre']),
    execStartPost: jsonString(json['exec_start_post']),
    execStart: jsonString(json['exec_start']),
    execStop: jsonString(json['exec_stop']),
    execReload: jsonString(json['exec_reload']),
    user: jsonString(json['user']),
    restart: jsonString(json['restart']),
    restartSec: jsonString(json['restart_sec']),
    restartMax: jsonInt(json['restart_max']),
    timeoutStartSec: jsonInt(json['timeout_start_sec']),
    timeoutStopSec: jsonInt(json['timeout_stop_sec']),
    environments: KvPair.listFrom(json['environments']),
    standardOutput: jsonString(json['standard_output']),
    standardError: jsonString(json['standard_error']),
    requires: jsonStringList(json['requires']),
    wants: jsonStringList(json['wants']),
    after: jsonStringList(json['after']),
    before: jsonStringList(json['before']),
    status: jsonString(json['status']),
    enabled: jsonBool(json['enabled']),
    pid: jsonInt(json['pid']),
    memory: jsonInt(json['memory']),
    cpu: jsonDouble(json['cpu']),
    uptime: jsonString(json['uptime']),
    memoryLimit: jsonDouble(json['memory_limit']),
    cpuQuota: jsonDouble(json['cpu_quota']),
    noNewPrivileges: jsonBool(json['no_new_privileges']),
    protectTmp: jsonBool(json['protect_tmp']),
    protectHome: jsonBool(json['protect_home']),
    protectSystem: jsonString(json['protect_system']),
    readWritePaths: jsonStringList(json['read_write_paths']),
    readOnlyPaths: jsonStringList(json['read_only_paths']),
  );

  /// 本地乐观更新用（切换自启 / 状态后无需整页刷新）。
  ProjectDetail copyWith({String? status, bool? enabled}) => ProjectDetail(
    id: id,
    name: name,
    type: type,
    description: description,
    rootDir: rootDir,
    workingDir: workingDir,
    execStartPre: execStartPre,
    execStartPost: execStartPost,
    execStart: execStart,
    execStop: execStop,
    execReload: execReload,
    user: user,
    restart: restart,
    restartSec: restartSec,
    restartMax: restartMax,
    timeoutStartSec: timeoutStartSec,
    timeoutStopSec: timeoutStopSec,
    environments: environments,
    standardOutput: standardOutput,
    standardError: standardError,
    requires: requires,
    wants: wants,
    after: after,
    before: before,
    status: status ?? this.status,
    enabled: enabled ?? this.enabled,
    pid: pid,
    memory: memory,
    cpu: cpu,
    uptime: uptime,
    memoryLimit: memoryLimit,
    cpuQuota: cpuQuota,
    noNewPrivileges: noNewPrivileges,
    protectTmp: protectTmp,
    protectHome: protectHome,
    protectSystem: protectSystem,
    readWritePaths: readWritePaths,
    readOnlyPaths: readOnlyPaths,
  );
}

/// 创建项目请求体，对应 `request.ProjectCreate`。
///
/// 注意：源码中 `Environments []types.KV` 未声明 json tag，创建接口无法可靠接收
/// 环境变量（官方前端同样不提交），因此这里不发送该字段，环境变量在编辑页配置。
class ProjectCreatePayload {
  const ProjectCreatePayload({
    required this.name,
    required this.type,
    this.description = '',
    this.rootDir = '',
    this.workingDir = '',
    this.execStart = '',
    this.user = '',
    this.restart = '',
  });

  /// 项目名称，需匹配 `^[a-zA-Z0-9_-]+$`（同时用作 systemd 服务名）。
  final String name;
  final String type;
  final String description;

  /// 留空时由面板取「项目默认目录 + 项目名」。
  final String rootDir;
  final String workingDir;
  final String execStart;
  final String user;
  final String restart;

  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type,
    'description': description,
    'root_dir': rootDir,
    'working_dir': workingDir,
    'exec_start': execStart,
    'user': user,
    'restart': restart,
  };
}

/// 更新项目请求体，对应 `request.ProjectUpdate`。
///
/// 面板的 `{id}` 路径参数在该结构上没有 `uri` tag，服务端实际从 **请求体**
/// 读取 `id`（官方前端亦如此），因此 body 必须带上 `id`。
class ProjectUpdatePayload {
  const ProjectUpdatePayload({
    required this.id,
    required this.name,
    required this.rootDir,
    this.description = '',
    this.workingDir = '',
    this.execStartPre = '',
    this.execStartPost = '',
    this.execStart = '',
    this.execStop = '',
    this.execReload = '',
    this.user = '',
    this.restart = '',
    this.restartSec = '',
    this.restartMax = 0,
    this.timeoutStartSec = 0,
    this.timeoutStopSec = 0,
    this.environments = const <KvPair>[],
    this.standardOutput = '',
    this.standardError = '',
    this.requires = const <String>[],
    this.wants = const <String>[],
    this.after = const <String>[],
    this.before = const <String>[],
    this.memoryLimit = 0,
    this.cpuQuota = '',
    this.noNewPrivileges = false,
    this.protectTmp = false,
    this.protectHome = false,
    this.protectSystem = '',
    this.readWritePaths = const <String>[],
    this.readOnlyPaths = const <String>[],
  });

  final int id;
  final String name;
  final String description;
  final String rootDir;
  final String workingDir;
  final String execStartPre;
  final String execStartPost;
  final String execStart;
  final String execStop;
  final String execReload;
  final String user;
  final String restart;
  final String restartSec;
  final int restartMax;
  final int timeoutStartSec;
  final int timeoutStopSec;
  final List<KvPair> environments;
  final String standardOutput;
  final String standardError;
  final List<String> requires;
  final List<String> wants;
  final List<String> after;
  final List<String> before;

  /// 内存限制（字节，0 表示不限制）。
  final double memoryLimit;

  /// CPU 限制，systemd 原样写入 `CPUQuota=`，如 `50%`、`200%`。
  final String cpuQuota;

  final bool noNewPrivileges;
  final bool protectTmp;
  final bool protectHome;
  final String protectSystem;
  final List<String> readWritePaths;
  final List<String> readOnlyPaths;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'root_dir': rootDir,
    'working_dir': workingDir,
    'exec_start_pre': execStartPre,
    'exec_start_post': execStartPost,
    'exec_start': execStart,
    'exec_stop': execStop,
    'exec_reload': execReload,
    'user': user,
    'restart': restart,
    'restart_sec': restartSec,
    'restart_max': restartMax,
    'timeout_start_sec': timeoutStartSec,
    'timeout_stop_sec': timeoutStopSec,
    'environments': environments.map((e) => e.toJson()).toList(),
    'standard_output': standardOutput,
    'standard_error': standardError,
    'requires': requires,
    'wants': wants,
    'after': after,
    'before': before,
    'memory_limit': memoryLimit,
    'cpu_quota': cpuQuota,
    'no_new_privileges': noNewPrivileges,
    'protect_tmp': protectTmp,
    'protect_home': protectHome,
    'protect_system': protectSystem,
    'read_write_paths': readWritePaths,
    'read_only_paths': readOnlyPaths,
  };
}
