/// 数据库服务器，对应源码 `internal/biz/database_server.go` 的 `DatabaseServer`。
class DatabaseServer {
  const DatabaseServer({
    required this.id,
    required this.name,
    required this.type,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.status,
    required this.remark,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String name;

  /// mysql / postgresql / redis / clickhouse / mongodb / sqlite / elasticsearch
  final String type;

  /// 主机地址（sqlite 时为数据库文件路径）。
  final String host;
  final int port;
  final String username;
  final String password;

  /// 连接状态：valid（正常）/ invalid（异常）。
  final String status;
  final String remark;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isValid => status == 'valid';

  /// 展示用地址。
  String get displayAddress => port > 0 ? '$host:$port' : host;

  factory DatabaseServer.fromJson(Map<String, dynamic> json) => DatabaseServer(
    id: (json['id'] as num?)?.toInt() ?? 0,
    name: json['name'] as String? ?? '',
    type: json['type'] as String? ?? '',
    host: json['host'] as String? ?? '',
    port: (json['port'] as num?)?.toInt() ?? 0,
    username: json['username'] as String? ?? '',
    password: json['password'] as String? ?? '',
    status: json['status'] as String? ?? '',
    remark: json['remark'] as String? ?? '',
    createdAt: _parseTime(json['created_at']),
    updatedAt: _parseTime(json['updated_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type,
    'host': host,
    'port': port,
    'username': username,
    'password': password,
    'status': status,
    'remark': remark,
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
