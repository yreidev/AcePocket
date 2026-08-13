import 'database_server.dart';

/// 数据库用户，对应源码 `internal/biz/database_user.go` 的 `DatabaseUser`。
class DatabaseUser {
  const DatabaseUser({
    required this.id,
    required this.serverId,
    required this.username,
    required this.password,
    required this.host,
    required this.status,
    required this.privileges,
    required this.remark,
    this.server,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int serverId;
  final String username;
  final String password;

  /// 仅 MySQL 使用（localhost / % / 指定主机）。
  final String host;

  /// valid（正常）/ invalid（异常），仅展示用。
  final String status;

  /// 授权的数据库列表，仅展示用。
  final List<String> privileges;
  final String remark;

  /// 关联的服务器（列表接口会带出）。
  final DatabaseServer? server;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isValid => status == 'valid';

  factory DatabaseUser.fromJson(Map<String, dynamic> json) => DatabaseUser(
    id: (json['id'] as num?)?.toInt() ?? 0,
    serverId: (json['server_id'] as num?)?.toInt() ?? 0,
    username: json['username'] as String? ?? '',
    password: json['password'] as String? ?? '',
    host: json['host'] as String? ?? '',
    status: json['status'] as String? ?? '',
    privileges:
        (json['privileges'] as List?)?.whereType<String>().toList(
          growable: false,
        ) ??
        const [],
    remark: json['remark'] as String? ?? '',
    server: json['server'] is Map<String, dynamic>
        ? DatabaseServer.fromJson(json['server'] as Map<String, dynamic>)
        : null,
    createdAt: _parseTime(json['created_at']),
    updatedAt: _parseTime(json['updated_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'server_id': serverId,
    'username': username,
    'password': password,
    'host': host,
    'status': status,
    'privileges': privileges,
    'remark': remark,
    if (server != null) 'server': server!.toJson(),
    // 字段为本地时区实例，序列化回 UTC 以保留绝对时刻（naive 串会丢偏移）。
    if (createdAt != null) 'created_at': createdAt!.toUtc().toIso8601String(),
    if (updatedAt != null) 'updated_at': updatedAt!.toUtc().toIso8601String(),
  };

  /// 解析面板返回的 RFC3339 时间（带时区偏移）。
  ///
  /// `DateTime.parse` 对带偏移的串返回 isUtc=true 的实例，直接展示会少 / 多算
  /// 时区差值，因此统一在解析处 `.toLocal()`，下游格式化即自动为本地时间。
  static DateTime? _parseTime(dynamic value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value)?.toLocal();
    }
    return null;
  }
}
