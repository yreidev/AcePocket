import 'json_utils.dart';

/// 备份文件（对应面板 `pkg/types/backup.go` 的 `BackupFile`）。
class BackupFile {
  const BackupFile({
    required this.name,
    required this.path,
    required this.size,
    this.time,
  });

  /// 文件名（删除接口传该值）。
  final String name;

  /// 服务端绝对路径（恢复接口传该值）。
  final String path;

  /// 已格式化的大小字符串（服务端直接返回，如 `1.20 MB`）。
  final String size;

  final DateTime? time;

  factory BackupFile.fromJson(Map<String, dynamic> json) => BackupFile(
    name: jsonString(json['name']),
    path: jsonString(json['path']),
    size: jsonString(json['size']),
    time: jsonTime(json['time']),
  );
}

/// 备份类型常量与展示文案（与 `request.BackupList` 的校验规则一致）。
class BackupTypes {
  const BackupTypes._();

  static const website = 'website';
  static const mysql = 'mysql';
  static const postgresql = 'postgresql';
  static const clickhouse = 'clickhouse';
  static const redis = 'redis';
  static const valkey = 'valkey';
  static const panel = 'panel';
  static const path = 'path';

  /// 列表接口允许的类型。
  static const listable = <String>[
    website,
    mysql,
    postgresql,
    clickhouse,
    redis,
    valkey,
    panel,
    path,
  ];

  /// 创建备份接口允许的类型（不含 path）。
  static const creatable = <String>[
    website,
    mysql,
    postgresql,
    clickhouse,
    redis,
    valkey,
    panel,
  ];

  /// 删除 / 恢复接口允许的类型（不含 path）。
  static const manageable = creatable;

  /// 数据库类型（需要选择库名）。
  static const databaseTypes = <String>[mysql, postgresql, clickhouse];

  static const labels = <String, String>{
    website: '网站',
    mysql: 'MySQL',
    postgresql: 'PostgreSQL',
    clickhouse: 'ClickHouse',
    redis: 'Redis',
    valkey: 'Valkey',
    panel: '面板',
    path: '目录',
  };

  static String label(String type) => labels[type] ?? type;

  /// 是否可以在本类型下创建备份。
  static bool canCreate(String type) =>
      creatable.contains(type) && type != panel;

  /// 是否可以删除 / 恢复本类型的备份文件。
  static bool canManage(String type) => manageable.contains(type);

  /// 是否可以恢复（面板自身备份需在面板端操作，不提供恢复目标）。
  static bool canRestore(String type) => canManage(type) && type != panel;
}
