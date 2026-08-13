import 'json_utils.dart';

/// 计划任务结构化配置（对应面板 `pkg/types/cron.go` 的 `CronConfig`）。
class CronConfig {
  const CronConfig({
    this.subType = '',
    this.flock = false,
    this.targets = const [],
    this.storage = 0,
    this.keep = 1,
    this.url = '',
    this.method = 'GET',
    this.headers = const {},
    this.body = '',
    this.timeout = 10,
    this.insecure = false,
    this.retries = 0,
  });

  /// 子类型：backup 时为 website/mysql/postgresql/clickhouse/redis/valkey/path；
  /// cutoff 时为 website/container。JSON 字段名为 `type`。
  final String subType;

  /// 进程锁：上次未执行完则跳过本次。
  final bool flock;

  /// 目标列表（网站名 / 数据库名 / 容器名 / 目录路径）。
  final List<String> targets;

  /// 备份存储 ID（0 表示本地存储）。
  final int storage;

  /// 保留份数。
  final int keep;

  // ---- URL 任务专用 ----
  final String url;
  final String method;
  final Map<String, String> headers;
  final String body;
  final int timeout;
  final bool insecure;
  final int retries;

  factory CronConfig.fromJson(Map<String, dynamic> json) {
    return CronConfig(
      subType: jsonString(json['type']),
      flock: jsonBool(json['flock']),
      targets: jsonStringList(json['targets']),
      storage: jsonInt(json['storage']),
      keep: json['keep'] == null ? 1 : jsonInt(json['keep']),
      url: jsonString(json['url']),
      method: json['method'] == null || jsonString(json['method']).isEmpty
          ? 'GET'
          : jsonString(json['method']),
      headers: jsonStringMap(json['headers']),
      body: jsonString(json['body']),
      timeout: json['timeout'] == null ? 10 : jsonInt(json['timeout']),
      insecure: jsonBool(json['insecure']),
      retries: jsonInt(json['retries']),
    );
  }

  Map<String, dynamic> toJson() => {
    'type': subType,
    'flock': flock,
    'targets': targets,
    'storage': storage,
    'keep': keep,
    'url': url,
    'method': method,
    'headers': headers,
    'body': body,
    'timeout': timeout,
    'insecure': insecure,
    'retries': retries,
  };
}

/// 计划任务（对应面板 `internal/biz/cron.go` 的 `Cron`）。
class Cron {
  const Cron({
    required this.id,
    required this.name,
    required this.status,
    required this.type,
    required this.time,
    required this.config,
    required this.shell,
    required this.log,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String name;

  /// 是否启用。
  final bool status;

  /// 任务类型：shell / backup / cutoff / url / synctime。
  final String type;

  /// crontab 表达式（5 段）。
  final String time;

  final CronConfig config;

  /// 服务端脚本文件绝对路径。
  final String shell;

  /// 服务端日志文件绝对路径。
  final String log;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Cron.fromJson(Map<String, dynamic> json) {
    final rawConfig = json['config'];
    return Cron(
      id: jsonInt(json['id']),
      name: jsonString(json['name']),
      status: jsonBool(json['status']),
      type: jsonString(json['type']),
      time: jsonString(json['time']),
      config: rawConfig is Map<String, dynamic>
          ? CronConfig.fromJson(rawConfig)
          : const CronConfig(),
      shell: jsonString(json['shell']),
      log: jsonString(json['log']),
      createdAt: jsonTime(json['created_at']),
      updatedAt: jsonTime(json['updated_at']),
    );
  }

  Cron copyWith({bool? status}) => Cron(
    id: id,
    name: name,
    status: status ?? this.status,
    type: type,
    time: time,
    config: config,
    shell: shell,
    log: log,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// 计划任务类型常量与展示文案。
class CronTypes {
  const CronTypes._();

  static const shell = 'shell';
  static const backup = 'backup';
  static const cutoff = 'cutoff';
  static const url = 'url';
  static const synctime = 'synctime';

  /// 创建时可选的全部类型（顺序与面板一致）。
  static const all = <String>[shell, backup, cutoff, url, synctime];

  static const labels = <String, String>{
    shell: '运行脚本',
    backup: '备份数据',
    cutoff: '日志切割',
    url: '访问 URL',
    synctime: '同步时间',
  };

  static String label(String type) => labels[type] ?? type;

  /// backup 子类型。
  static const backupSubTypes = <String, String>{
    'website': '网站',
    'mysql': 'MySQL 数据库',
    'postgresql': 'PostgreSQL 数据库',
    'clickhouse': 'ClickHouse 数据库',
    'redis': 'Redis',
    'valkey': 'Valkey',
    'path': '目录',
  };

  /// cutoff 子类型。
  static const cutoffSubTypes = <String, String>{
    'website': '网站',
    'container': '容器',
  };

  /// URL 任务可选请求方法。
  static const httpMethods = <String>[
    'GET',
    'POST',
    'PUT',
    'DELETE',
    'PATCH',
    'HEAD',
  ];

  static String subTypeLabel(String type, String subType) {
    if (type == backup) return backupSubTypes[subType] ?? subType;
    if (type == cutoff) return cutoffSubTypes[subType] ?? subType;
    return subType;
  }
}
